#!/usr/bin/env bash
# Raspberry Pi Wi-Fi AP + WireGuard client bootstrap
# Author: <you>
# Version: 1.3 – 2025-05-22
set -euo pipefail
IFS=$'\n\t'

################################################################################
#                               Utility helpers                                #
################################################################################
die()      { echo "[FATAL] $*" >&2; exit 1; }
yesno()    { local q=$1; read -rp "$q [y/N] " ans; [[ ${ans,,} == y ]]; }
backup()   { local f=$1; cp -a "$f" "${f}.bak.$(date +%s)"; }

prompt() {
  # $1 var, $2 msg, $3 default, $4 regex
  local _var=$1 msg=$2 def=$3 re=$4 v
  while true; do
    read -rp "$msg [$def]: " v; v=${v:-$def}
    [[ $v =~ $re ]] || { echo "Invalid value."; continue; }
    yesno "Confirm '$v'?" && break
  done
  printf -v "$_var" %s "$v"
}

cleanup() {
  echo "[WARN] Aborted – rolling back."
  [[ -f /etc/dhcpcd.conf.bak* ]] && mv /etc/dhcpcd.conf.bak* /etc/dhcpcd.conf
  systemctl stop hostapd dnsmasq || true
  iptables -t nat -D POSTROUTING -s ${WIFI_PREFIX}.0/24 -o wg0 -j MASQUERADE 2>/dev/null || true
}
trap cleanup ERR INT

################################################################################
#                                Input prompts                                 #
################################################################################
[[ $(id -u) -eq 0 ]] || die "Run as root."

echo "=== Raspberry Pi WireGuard + Wi-Fi AP installer ==="

prompt WG_SERVER_PUB "WireGuard server public key"   ""  '^[A-Za-z0-9+/]{43}=$'
prompt WG_ENDPOINT   "WireGuard server endpoint (IP:port)" "" '^[0-9.]+:[0-9]{1,5}$'
prompt VPN_SUBNET    "VPN subnet (CIDR)"           "10.0.0.0/24" '^[0-9./]+$'
# More robust IP calculation
VPN_NET_PREFIX=$(echo "$VPN_SUBNET" | cut -d'/' -f1 | sed 's/\.[0-9]*$//')
VPN_CLIENT_IP="${VPN_NET_PREFIX}.2/32"

prompt WIFI_SSID     "Wi-Fi SSID"                  "MySecureAP"  '^.{1,32}$'
prompt WIFI_PASS     "Wi-Fi password (8-63 chars)" ""  '^.{8,63}$'
prompt WIFI_CC       "Country code (ISO-3166-1-alpha-2)" "FR" '^[A-Z]{2}$'
prompt WIFI_CH       "Wi-Fi channel (1-11 2.4 GHz, 36/40/44/48/149/153/157/161/165 5 GHz)" "6" '^(1[0-1]|[1-9]|3[6]|4[0]|4[4]|4[8]|14[9]|15[3]|15[7]|16[1]|16[5])$'
prompt WIFI_IP       "AP IP address"               "192.168.50.1" '^[0-9.]+$'

WIFI_PREFIX=$(cut -d. -f1-3 <<<"$WIFI_IP")
DHCP_START=${WIFI_PREFIX}.10
DHCP_END=${WIFI_PREFIX}.150

echo
cat <<EOF
========= Summary =========
WG pubkey : $WG_SERVER_PUB
WG endpoint : $WG_ENDPOINT
VPN subnet / client IP : $VPN_SUBNET / $VPN_CLIENT_IP
SSID / pass : $WIFI_SSID / $WIFI_PASS
Country / channel : $WIFI_CC / $WIFI_CH
AP IP / DHCP range : $WIFI_IP  ($DHCP_START – $DHCP_END)
============================
EOF
yesno "Proceed with installation?" || die "Cancelled."

################################################################################
#                             Package installation                             #
################################################################################
echo "[INFO] Updating and installing packages..."
apt update -y
apt install -y wireguard wireguard-tools hostapd dnsmasq iptables-persistent dhcpcd5 chrony

################################################################################
#                        Static IP & dhcpcd configuration                       #
################################################################################
backup /etc/dhcpcd.conf
sed -i '/^interface wlan0/,+3 d' /etc/dhcpcd.conf
cat >> /etc/dhcpcd.conf <<EOF

# Added by WG-AP installer
interface wlan0
static ip_address=${WIFI_IP}/24
nohook wpa_supplicant
EOF
systemctl restart dhcpcd

################################################################################
#                        Chrony configuration for VPN                          #
################################################################################
echo "[INFO] Configuring chrony for VPN..."
mkdir -p /etc/chrony/sources.d/
cat > /etc/chrony/sources.d/vpn.sources <<EOF
pool time.cloudflare.com iburst
server time.google.com iburst
EOF
systemctl restart chrony

################################################################################
#                              Hostapd setup                                   #
################################################################################
echo "[INFO] Setting up hostapd..."
cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
country_code=$WIFI_CC

ssid=$WIFI_SSID
hw_mode=$( [[ $WIFI_CH -ge 36 ]] && echo a || echo g )
channel=$WIFI_CH

ieee80211n=1
ieee80211d=1
wmm_enabled=1

wpa=2
wpa_passphrase=$WIFI_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

sed -i 's|^#\?DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
systemctl enable --now hostapd

################################################################################
#                              Dnsmasq setup                                   #
################################################################################
echo "[INFO] Configuring dnsmasq..."
backup /etc/dnsmasq.conf
cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,24h
dhcp-option=3,$WIFI_IP
dhcp-option=6,9.9.9.9,1.1.1.1
EOF
systemctl restart dnsmasq

################################################################################
#                            WireGuard client                                  #
################################################################################
echo "[INFO] Creating WireGuard client config..."
install -o root -g root -m 700 -d /etc/wireguard
cd /etc/wireguard
CLIENT_PRIV=$(wg genkey)
CLIENT_PUB=$(sed 's/$/\n/' <<<"$CLIENT_PRIV" | wg pubkey)

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
PrivateKey = $CLIENT_PRIV
Address = $VPN_CLIENT_IP
DNS = 9.9.9.9

[Peer]
PublicKey = $WG_SERVER_PUB
Endpoint = $WG_ENDPOINT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
chmod 600 /etc/wireguard/wg0.conf
systemctl enable --now wg-quick@wg0

################################################################################
#                          IP forwarding & NAT                                 #
################################################################################
echo "[INFO] Enabling IP forwarding and NAT..."
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ip_forward.conf
sysctl --system

# Wait for WireGuard to establish connection and update routes
sleep 3
# Verify wg0 is up before configuring NAT
if ! ip link show wg0 &>/dev/null; then
    die "WireGuard interface wg0 not found"
fi

# Use wg0 explicitly for NAT since all traffic should go through VPN
iptables -t nat -C POSTROUTING -s ${WIFI_PREFIX}.0/24 -o wg0 -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -s ${WIFI_PREFIX}.0/24 -o wg0 -j MASQUERADE
iptables-save > /etc/iptables/rules.v4
systemctl enable netfilter-persistent

################################################################################
#                               Finish                                         #
################################################################################
cat <<EOF

========================================================
   ✔  Installation completed – reboot recommended
========================================================
• Client public key : $CLIENT_PUB
• VPN interface     : wg0
• AP SSID           : $WIFI_SSID   (password: $WIFI_PASS)
• LAN range         : ${WIFI_PREFIX}.0/24 via wlan0
--------------------------------------------------------
Remember to add the client public key & 10.0.0.2/32 to
your **VPS** server with:

  sudo wg set wg0 peer $CLIENT_PUB allowed-ips ${VPN_CLIENT_IP%/*}/32

Then run 'reboot' or power-cycle the Pi.
========================================================
EOF
