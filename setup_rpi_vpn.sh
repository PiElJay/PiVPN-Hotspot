#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# Raspberry Pi - WiFi Access Point + WireGuard VPN Client                     #
# ----------------------------------------------------------------------------#
# - Asks user for necessary inputs (WireGuard, SSID, password, etc.)          #
# - Sets up an AP on wlan0 with a static IP via dhcpcd                        #
# - Installs and configures hostapd, dnsmasq, wireguard, iptables-persistent  #
# - Routes Wi-Fi traffic through eth0 and wg0                                 #
###############################################################################

# Ensure script is run as root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "[ERROR] Please run the script as root (sudo su)."
  exit 1
fi

echo "==============================================="
echo "  🛠️  Raspberry Pi VPN Access Point Setup     "
echo "==============================================="

###############################################################################
# 1. USER INPUTS                                                              #
###############################################################################

# WireGuard
read -rp "Enter WireGuard Server Public Key: " WG_SERVER_PUBKEY
read -rp "Enter WireGuard Server IP (e.g., 209.227.234.177:51820): " WG_SERVER_IP
read -rp "Enter VPN subnet [default 10.0.0.0/24]: " VPN_SUBNET
VPN_SUBNET=${VPN_SUBNET:-10.0.0.0/24}

# Calculate client IP (replace '0/24' with '2')
VPN_CLIENT_IP=$(echo "$VPN_SUBNET" | sed 's/0\/24/2/')

# Wi-Fi
read -rp "Enter Wi-Fi SSID (e.g., MySecureAP): " WIFI_SSID
read -rp "Enter Wi-Fi Password: " WIFI_PASS
read -rp "Enter Wi-Fi Country Code [default FR]: " WIFI_COUNTRY
WIFI_COUNTRY=${WIFI_COUNTRY:-FR}
read -rp "Enter Wi-Fi Channel [default 6]: " WIFI_CHANNEL
WIFI_CHANNEL=${WIFI_CHANNEL:-6}

# AP IP Configuration
read -rp "Enter AP IP (e.g., 192.168.50.1) [default 192.168.50.1]: " WIFI_IP
WIFI_IP=${WIFI_IP:-192.168.50.1}

# Extract network prefix (e.g., 192.168.50)
WIFI_PREFIX=$(echo "$WIFI_IP" | cut -d '.' -f1-3)
DHCP_RANGE_START="${WIFI_PREFIX}.10"
DHCP_RANGE_END="${WIFI_PREFIX}.150"

# Confirm user choices
echo ""
echo "📌  Configuration Summary:"
echo "-----------------------------------------------"
echo "🔹 WireGuard Server PubKey:  $WG_SERVER_PUBKEY"
echo "🔹 WireGuard Server Endpoint: $WG_SERVER_IP"
echo "🔹 VPN Subnet:                $VPN_SUBNET"
echo "🔹 VPN Client IP:             $VPN_CLIENT_IP"
echo "🔹 Wi-Fi SSID:                $WIFI_SSID"
echo "🔹 Wi-Fi Password:            $WIFI_PASS"
echo "🔹 Wi-Fi Country:             $WIFI_COUNTRY"
echo "🔹 Wi-Fi Channel:             $WIFI_CHANNEL"
echo "🔹 AP IP:                     $WIFI_IP"
echo "-----------------------------------------------"

read -rp "⚠️  Proceed with these settings? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
  echo "[INFO] User aborted. Exiting..."
  exit 1
fi

###############################################################################
# 2. INSTALL REQUIRED PACKAGES                                                #
###############################################################################
echo "[INFO] Updating system and installing necessary packages..."
apt update && apt full-upgrade -y
apt install -y git curl hostapd dnsmasq wireguard iptables-persistent dhcpcd5

###############################################################################
# 3. SET STATIC IP FOR WLAN0 (DHCPCD)                                         #
###############################################################################
echo "[INFO] Setting static IP for wlan0 in /etc/dhcpcd.conf..."
sed -i '/^interface wlan0/,+3 d' /etc/dhcpcd.conf

cat <<EOF >> /etc/dhcpcd.conf

interface wlan0
static ip_address=${WIFI_IP}/24
nohook wpa_supplicant
EOF

systemctl enable dhcpcd
systemctl restart dhcpcd

###############################################################################
# 4. CONFIGURE HOSTAPD (WiFi Access Point)                                    #
###############################################################################
echo "[INFO] Configuring hostapd..."
systemctl unmask hostapd
systemctl enable hostapd

cat <<EOF > /etc/hostapd/hostapd.conf
interface=wlan0
driver=nl80211
country_code=$WIFI_COUNTRY

ssid=$WIFI_SSID
hw_mode=g
channel=$WIFI_CHANNEL

# Enable 802.11n
ieee80211n=1
wmm_enabled=1

auth_algs=1
ignore_broadcast_ssid=0

wpa=2
wpa_passphrase=$WIFI_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

# Ensure DAEMON_CONF points to hostapd.conf
if grep -q '^#DAEMON_CONF=' /etc/default/hostapd; then
  sed -i "s|^#DAEMON_CONF=.*|DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"|" /etc/default/hostapd
elif grep -q '^DAEMON_CONF=' /etc/default/hostapd; then
  sed -i "s|^DAEMON_CONF=.*|DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"|" /etc/default/hostapd
else
  echo "DAEMON_CONF=\"/etc/hostapd/hostapd.conf\"" >> /etc/default/hostapd
fi

###############################################################################
# 5. CONFIGURE DNSMASQ (DHCP for Clients)                                     #
###############################################################################
echo "[INFO] Configuring dnsmasq..."
cat <<EOF > /etc/dnsmasq.conf
interface=wlan0
dhcp-range=$DHCP_RANGE_START,$DHCP_RANGE_END,255.255.255.0,24h
dhcp-option=3,$WIFI_IP
dhcp-option=6,8.8.8.8,1.1.1.1
EOF

systemctl enable dnsmasq
systemctl restart dnsmasq

###############################################################################
# 6. ENABLE IP FORWARDING & NAT (iptables)                                    #
###############################################################################
echo "[INFO] Enabling IP forwarding and configuring NAT..."
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ip_forward.conf
sysctl --system

iptables -t nat -A POSTROUTING -s ${WIFI_PREFIX}.0/24 -o eth0 -j MASQUERADE
iptables-save > /etc/iptables/rules.v4

systemctl enable netfilter-persistent
netfilter-persistent save

###############################################################################
# 7. REBOOT SYSTEM                                                            #
###############################################################################
echo "[INFO] Installation and configuration completed! Rebooting in 3 seconds..."
sleep 3
reboot
