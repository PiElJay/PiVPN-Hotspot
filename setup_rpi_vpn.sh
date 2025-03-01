#!/usr/bin/env bash
set -euo pipefail

################################################################################
# Raspberry Pi - WiFi Access Point + WireGuard VPN Client                      #
# ---------------------------------------------------------------------------- #
# This script turns a Raspberry Pi into:                                       #
# - A Wi-Fi Access Point (AP) on wlan0                                         #
# - A VPN client, routing all traffic through a WireGuard VPS                 #
# - A NAT Gateway for forwarding traffic from connected devices               #
# ---------------------------------------------------------------------------- #
# The script will ask for necessary inputs before execution.                   #
################################################################################

# Ensure script runs as root
if [[ $(id -u) -ne 0 ]]; then
  echo "[ERROR] Please run this script as root (sudo su)."
  exit 1
fi

################################################################################
# 1. USER INPUTS                                                               #
################################################################################

echo "==============================================="
echo "  🛠️  Raspberry Pi VPN Access Point Setup     "
echo "==============================================="
echo ""

# Ask for VPN settings
read -rp "Enter your WireGuard Server Public Key: " WG_SERVER_PUBKEY
read -rp "Enter your WireGuard Server IP (e.g., 209.227.234.177:51820): " WG_SERVER_IP
read -rp "Enter VPN subnet (default 10.0.0.0/24): " VPN_SUBNET
VPN_SUBNET=${VPN_SUBNET:-10.0.0.0/24}

# Ask for Wi-Fi settings
read -rp "Enter Wi-Fi SSID (e.g., MySecureAP): " WIFI_SSID
read -rp "Enter Wi-Fi Password: " WIFI_PASS

# Set VPN client IP (calculated from subnet)
VPN_CLIENT_IP=$(echo "$VPN_SUBNET" | sed 's/0\/24/2/')

echo ""
echo "📌 Configuration Summary:"
echo "-----------------------------------------------"
echo "🔹 WireGuard Server Public Key: $WG_SERVER_PUBKEY"
echo "🔹 WireGuard Server IP: $WG_SERVER_IP"
echo "🔹 VPN Subnet: $VPN_SUBNET"
echo "🔹 VPN Client IP: $VPN_CLIENT_IP"
echo "🔹 Wi-Fi SSID: $WIFI_SSID"
echo "🔹 Wi-Fi Password: $WIFI_PASS"
echo "-----------------------------------------------"

read -rp "⚠️  Continue with these settings? (y/n): " CONFIRM
if [[ $CONFIRM != "y" ]]; then
  echo "[INFO] Exiting..."
  exit 1
fi

################################################################################
# 2. INSTALL REQUIRED PACKAGES                                                 #
################################################################################

echo "[INFO] Updating system and installing required packages..."
apt update && apt full-upgrade -y
apt install -y git curl hostapd dnsmasq wireguard iptables-persistent

################################################################################
# 3. SYSTEM CONFIGURATION                                                      #
################################################################################

echo "[INFO] Setting hostname and Wi-Fi country..."
hostnamectl set-hostname raspberry-vpn
echo "raspberry-vpn" > /etc/hostname
echo "127.0.1.1 raspberry-vpn" >> /etc/hosts
echo "country=FR" >> /etc/wpa_supplicant/wpa_supplicant.conf

################################################################################
# 4. CONFIGURE WI-FI ACCESS POINT                                              #
################################################################################

echo "[INFO] Configuring Wi-Fi Access Point..."
systemctl unmask hostapd
systemctl enable hostapd

cat <<EOF > /etc/hostapd/hostapd.conf
interface=wlan0
ssid=$WIFI_SSID
hw_mode=g
channel=6
wpa=2
wpa_passphrase=$WIFI_PASS
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
country_code=FR
EOF

cat <<EOF > /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.50.10,192.168.50.150,255.255.255.0,24h
dhcp-option=3,192.168.50.1
dhcp-option=6,8.8.8.8,1.1.1.1
EOF

################################################################################
# 5. ENABLE NAT, IP FORWARDING & IPTABLES RULES                                #
################################################################################

echo "[INFO] Enabling IP forwarding and setting iptables rules..."
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ip_forward.conf
sysctl --system

iptables -t nat -A POSTROUTING -s 192.168.50.0/24 -o eth0 -j MASQUERADE
iptables -t nat -A POSTROUTING -s 192.168.50.0/24 -o wg0 -j MASQUERADE
iptables -A FORWARD -i wlan0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o wg0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -o wlan0 -j ACCEPT
iptables -A FORWARD -i wg0 -o wlan0 -j ACCEPT

iptables-save > /etc/iptables/rules.v4
ip6tables-save > /etc/iptables/rules.v6

systemctl enable netfilter-persistent
netfilter-persistent save

################################################################################
# 6. CONFIGURE WIREGUARD CLIENT                                                #
################################################################################

echo "[INFO] Configuring WireGuard client..."
mkdir -p /etc/wireguard && chmod 700 /etc/wireguard
cd /etc/wireguard
umask 077

# Generate private key if not exists
if [[ ! -f client_private.key ]]; then
  wg genkey | tee client_private.key | wg pubkey > client_public.key
fi
CLIENT_PRIVATE_KEY="$(cat client_private.key)"

cat <<EOF > /etc/wireguard/wg0.conf
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $VPN_CLIENT_IP/24
DNS = 8.8.8.8

[Peer]
PublicKey = $WG_SERVER_PUBKEY
Endpoint = $WG_SERVER_IP
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 /etc/wireguard/wg0.conf

################################################################################
# 7. FINAL SETUP & REBOOT                                                      #
################################################################################

echo "[INFO] Setup complete! Rebooting..."
sleep 3
reboot
