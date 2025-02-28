#!/usr/bin/env bash
set -euo pipefail

################################################################################
# Raspberry Pi - WiFi Access Point + WireGuard VPN Client                      #
# ---------------------------------------------------------------------------- #
# This script turns a Raspberry Pi into:                                       #
# - A Wi-Fi Access Point (AP) on wlan0                                         #
# - A VPN client, routing all traffic through a WireGuard VPS                  #
# - A NAT Gateway for forwarding traffic from connected devices                #
# ---------------------------------------------------------------------------- #
# After execution, the Raspberry Pi will reboot.                               #
################################################################################

# Ensure script runs as root
if [[ $(id -u) -ne 0 ]]; then
  echo "[ERROR] Please run this script as root (sudo su)."
  exit 1
fi

echo "[INFO] Updating system and installing required packages..."
apt update && apt full-upgrade -y
apt install -y git curl hostapd dnsmasq wireguard

# Install iptables and openresolv if missing
if ! command -v iptables &> /dev/null; then
  echo "[INFO] Installing iptables..."
  apt install -y iptables iptables-persistent
fi

if ! command -v resolvconf &> /dev/null; then
  echo "[INFO] Installing openresolv (resolvconf)..."
  apt install -y openresolv
fi

################################################################################
# 1. SYSTEM CONFIGURATION (HOSTNAME & WIFI COUNTRY)                            #
################################################################################

echo "[INFO] Setting hostname and Wi-Fi country..."
hostnamectl set-hostname raspberry-vpn
echo "raspberry-vpn" > /etc/hostname
echo "127.0.1.1 raspberry-vpn" >> /etc/hosts

# Set Wi-Fi country
echo "country=FR" >> /etc/wpa_supplicant/wpa_supplicant.conf

################################################################################
# 2. SET STATIC IP ON WLAN0                                                    #
################################################################################

echo "[INFO] Setting static IP for wlan0..."
cat <<EOF > /etc/dhcpcd.conf
interface wlan0
    static ip_address=192.168.50.1/24
    nohook wpa_supplicant
EOF

################################################################################
# 3. CONFIGURE WI-FI ACCESS POINT                                              #
################################################################################

echo "[INFO] Configuring Wi-Fi Access Point..."
systemctl unmask hostapd
systemctl enable hostapd

# Configure hostapd (Wi-Fi AP settings)
cat <<EOF > /etc/hostapd/hostapd.conf
interface=wlan0
ssid=MySecureAP
hw_mode=g
channel=6
wpa=2
wpa_passphrase=ChangeThisPassword!
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
country_code=FR
EOF

# Configure dnsmasq (DHCP for AP clients)
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak || true
cat <<EOF > /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.50.10,192.168.50.150,255.255.255.0,24h
dhcp-option=3,192.168.50.1
dhcp-option=6,8.8.8.8,1.1.1.1
EOF

################################################################################
# 4. ENABLE NAT & IP FORWARDING                                                #
################################################################################

echo "[INFO] Enabling IP forwarding and setting iptables rules..."
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ip_forward.conf
sysctl --system

# Set iptables rules for NAT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i wlan0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -o wlan0 -j ACCEPT

# Save iptables rules
iptables-save > /etc/iptables.up.rules

# Restore iptables on boot
cat <<EOF > /etc/network/if-pre-up.d/iptables
#!/bin/sh
/sbin/iptables-restore < /etc/iptables.up.rules
EOF
chmod +x /etc/network/if-pre-up.d/iptables

################################################################################
# 5. CONFIGURE WIREGUARD CLIENT                                                #
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
Address = 10.0.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = ReplaceWithYourVPSPublicKey
Endpoint = ReplaceWithYourVPSIP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 /etc/wireguard/wg0.conf

################################################################################
# 6. ENABLE SERVICES                                                           #
################################################################################

echo "[INFO] Enabling and starting services..."
systemctl enable dnsmasq
systemctl enable hostapd
systemctl restart dnsmasq
systemctl restart hostapd

# Enable and start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

################################################################################
# 7. VPN WATCHDOG (AUTO-RESTART VPN IF DOWN)                                   #
################################################################################

echo "[INFO] Creating VPN watchdog script..."
cat <<EOF > /usr/local/bin/vpn-watchdog
#!/bin/bash
if ! ping -c 3 10.0.0.1 &> /dev/null; then
    systemctl restart wg-quick@wg0
    logger "VPN Watchdog: Tunnel restarted"
fi
EOF
chmod +x /usr/local/bin/vpn-watchdog

# Add cron job to check VPN every 2 minutes
if ! crontab -l 2>/dev/null | grep -q vpn-watchdog; then
  (crontab -l 2>/dev/null; echo "*/2 * * * * /usr/local/bin/vpn-watchdog") | crontab -
fi

################################################################################
# 8. FINAL SETUP & REBOOT                                                      #
################################################################################

echo "[INFO] Setup complete! Rebooting..."
sleep 3
reboot
#!/usr/bin/env bash
set -euo pipefail

################################################################################
# Raspberry Pi - WiFi Access Point + WireGuard VPN Client                      #
# ---------------------------------------------------------------------------- #
# This script turns a Raspberry Pi into:                                       #
# - A Wi-Fi Access Point (AP) on wlan0                                         #
# - A VPN client, routing all traffic through a WireGuard VPS                  #
# - A NAT Gateway for forwarding traffic from connected devices                #
# ---------------------------------------------------------------------------- #
# After execution, the Raspberry Pi will reboot.                               #
################################################################################

# Ensure script runs as root
if [[ $(id -u) -ne 0 ]]; then
  echo "[ERROR] Please run this script as root (sudo su)."
  exit 1
fi

echo "[INFO] Updating system and installing required packages..."
apt update && apt full-upgrade -y
apt install -y git curl hostapd dnsmasq wireguard

# Install iptables and openresolv if missing
if ! command -v iptables &> /dev/null; then
  echo "[INFO] Installing iptables..."
  apt install -y iptables iptables-persistent
fi

if ! command -v resolvconf &> /dev/null; then
  echo "[INFO] Installing openresolv (resolvconf)..."
  apt install -y openresolv
fi

################################################################################
# 1. SYSTEM CONFIGURATION (HOSTNAME & WIFI COUNTRY)                            #
################################################################################

echo "[INFO] Setting hostname and Wi-Fi country..."
hostnamectl set-hostname raspberry-vpn
echo "raspberry-vpn" > /etc/hostname
echo "127.0.1.1 raspberry-vpn" >> /etc/hosts

# Set Wi-Fi country
echo "country=FR" >> /etc/wpa_supplicant/wpa_supplicant.conf

################################################################################
# 2. SET STATIC IP ON WLAN0                                                    #
################################################################################

echo "[INFO] Setting static IP for wlan0..."
cat <<EOF > /etc/dhcpcd.conf
interface wlan0
    static ip_address=192.168.50.1/24
    nohook wpa_supplicant
EOF

################################################################################
# 3. CONFIGURE WI-FI ACCESS POINT                                              #
################################################################################

echo "[INFO] Configuring Wi-Fi Access Point..."
systemctl unmask hostapd
systemctl enable hostapd

# Configure hostapd (Wi-Fi AP settings)
cat <<EOF > /etc/hostapd/hostapd.conf
interface=wlan0
ssid=MySecureAP
hw_mode=g
channel=6
wpa=2
wpa_passphrase=ChangeThisPassword!
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
country_code=FR
EOF

# Configure dnsmasq (DHCP for AP clients)
mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak || true
cat <<EOF > /etc/dnsmasq.conf
interface=wlan0
dhcp-range=192.168.50.10,192.168.50.150,255.255.255.0,24h
dhcp-option=3,192.168.50.1
dhcp-option=6,8.8.8.8,1.1.1.1
EOF

################################################################################
# 4. ENABLE NAT & IP FORWARDING                                                #
################################################################################

echo "[INFO] Enabling IP forwarding and setting iptables rules..."
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ip_forward.conf
sysctl --system

# Set iptables rules for NAT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i wlan0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i eth0 -o wlan0 -j ACCEPT

# Save iptables rules
iptables-save > /etc/iptables.up.rules

# Restore iptables on boot
cat <<EOF > /etc/network/if-pre-up.d/iptables
#!/bin/sh
/sbin/iptables-restore < /etc/iptables.up.rules
EOF
chmod +x /etc/network/if-pre-up.d/iptables

################################################################################
# 5. CONFIGURE WIREGUARD CLIENT                                                #
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
Address = 10.0.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = ReplaceWithYourVPSPublicKey
Endpoint = ReplaceWithYourVPSIP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 /etc/wireguard/wg0.conf

################################################################################
# 6. ENABLE SERVICES                                                           #
################################################################################

echo "[INFO] Enabling and starting services..."
systemctl enable dnsmasq
systemctl enable hostapd
systemctl restart dnsmasq
systemctl restart hostapd

# Enable and start WireGuard
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

################################################################################
# 7. VPN WATCHDOG (AUTO-RESTART VPN IF DOWN)                                   #
################################################################################

echo "[INFO] Creating VPN watchdog script..."
cat <<EOF > /usr/local/bin/vpn-watchdog
#!/bin/bash
if ! ping -c 3 10.0.0.1 &> /dev/null; then
    systemctl restart wg-quick@wg0
    logger "VPN Watchdog: Tunnel restarted"
fi
EOF
chmod +x /usr/local/bin/vpn-watchdog

# Add cron job to check VPN every 2 minutes
if ! crontab -l 2>/dev/null | grep -q vpn-watchdog; then
  (crontab -l 2>/dev/null; echo "*/2 * * * * /usr/local/bin/vpn-watchdog") | crontab -
fi

################################################################################
# 8. FINAL SETUP & REBOOT                                                      #
################################################################################

echo "[INFO] Setup complete! Rebooting..."
sleep 3
reboot
