#!/usr/bin/env bash
set -euo pipefail

################################################################################
# WIREGUARD SERVER SETUP ON UBUNTU 24.04 (NOBLE)                               #
# ---------------------------------------------------------------------------- #
# This script sets up a WireGuard VPN server on a VPS running Ubuntu 24.04.    #
# - Uses UFW as the firewall, enabling NAT and IP forwarding.                  #
# - Network interface: enx5 (replace with your actual interface).               #
# - Public IP: 209.227.234.177 (update accordingly).                            #
# - Full tunnel configuration (AllowedIPs = 0.0.0.0/0).                         #
# - Includes a watchdog to monitor client handshakes.                          #
################################################################################

# ----- REQUIRE ROOT PRIVILEGES -----
if [[ $(id -u) -ne 0 ]]; then
  echo "[ERROR] Please run this script as root (sudo su)."
  exit 1
fi

echo "[INFO] Updating system and installing required packages..."
apt update && apt upgrade -y

echo "[INFO] Installing WireGuard and UFW..."
apt install -y wireguard ufw

################################################################################
# 1. ENABLE IP FORWARDING & CONFIGURE UFW NAT
################################################################################
echo "[INFO] Enabling net.ipv4.ip_forward for full tunnel..."
if ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf; then
  echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi
sysctl -p

# Configure NAT (MASQUERADE) in UFW by modifying /etc/ufw/before.rules
echo "[INFO] Setting up NAT in /etc/ufw/before.rules (MASQUERADE on enx5)"

UFW_BEFORE="/etc/ufw/before.rules"
BACKUP_FILE="/etc/ufw/before.rules.bak.$(date +%Y%m%d%H%M%S)"

# Backup existing rules before modifying
cp "$UFW_BEFORE" "$BACKUP_FILE"

# If NAT rule is missing, add it at the beginning of the file
if ! grep -q 'POSTROUTING -o enx5 -j MASQUERADE' "$UFW_BEFORE"; then
  sed -i '1 i\
*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -o enx5 -j MASQUERADE\nCOMMIT\n' "$UFW_BEFORE"
fi

################################################################################
# 2. CONFIGURE UFW FIREWALL RULES
################################################################################
echo "[INFO] Configuring UFW: opening WireGuard (51820/udp) and SSH (22/tcp)"
ufw allow 22/tcp || true      # Ensure SSH is always accessible
ufw allow 51820/udp || true   # Allow WireGuard VPN traffic
ufw enable
ufw status verbose

################################################################################
# 3. GENERATE SERVER KEYS & CONFIGURE /etc/wireguard/wg0.conf
################################################################################
echo "[INFO] Generating WireGuard keys (server_private.key, server_public.key)"
cd /etc/wireguard || exit 1
umask 077  # Secure permissions

# Generate private & public keys if not already present
if [[ ! -f server_private.key ]]; then
  wg genkey | tee server_private.key | wg pubkey > server_public.key
fi
SERVER_PRIVATE_KEY=$(cat server_private.key)
SERVER_PUBLIC_KEY=$(cat server_public.key)

echo "[INFO] Creating /etc/wireguard/wg0.conf configuration file"
cat <<EOF > /etc/wireguard/wg0.conf
[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = $SERVER_PRIVATE_KEY
# Uncomment to let WireGuard dynamically save peers
# SaveConfig = true

# PostUp/PostDown iptables rules (not needed if using UFW, but kept as fallback)
# PostUp   = iptables -t nat -A POSTROUTING -o enx5 -j MASQUERADE
# PostDown = iptables -t nat -D POSTROUTING -o enx5 -j MASQUERADE

# EXAMPLE CLIENT PEER (Replace with your Raspberry Pi's public key)
[Peer]
PublicKey = uGsP3Es3SCTtElTS8s99CQ2RIJn4i8d2jgom6q1IVEg=
AllowedIPs = 10.0.0.2/32
EOF

# Secure file permissions
chmod 600 /etc/wireguard/*

################################################################################
# 4. ENABLE & START WIREGUARD
################################################################################
echo "[INFO] Enabling WireGuard service to start on boot"
systemctl enable wg-quick@wg0
wg-quick up wg0

echo "[INFO] WireGuard status after startup:"
wg

################################################################################
# 5. WATCHDOG: MONITOR CLIENT HANDSHAKES
################################################################################
echo "[INFO] Setting up a WireGuard watchdog script..."

WATCHDOG_SCRIPT="/usr/local/bin/wg-watchdog"

cat <<'EOF' > "$WATCHDOG_SCRIPT"
#!/usr/bin/env bash
# Simple watchdog script to monitor client handshake.
# Requires PersistentKeepalive > 0 on the client.
# If no handshake for more than 120s, restart wg0.

PEER_PUBKEY="<CLIENT_PUBLIC_KEY>"  # Replace with actual client public key
LAST_HANDSHAKE=$(wg show wg0 latest-handshakes | grep "$PEER_PUBKEY" | awk '{print $2}')
CURRENT_TIME=$(date +%s)

if [[ -n "$LAST_HANDSHAKE" ]]; then
  DIFF=$(( CURRENT_TIME - LAST_HANDSHAKE ))
  if [[ $DIFF -gt 120 ]]; then
    logger "wg-watchdog: No handshake for $DIFF seconds. Restarting wg0."
    systemctl restart wg-quick@wg0
  fi
fi
EOF

# Make the watchdog script executable
chmod +x "$WATCHDOG_SCRIPT"

# Add a cron job to check VPN status every 2 minutes
if ! crontab -l 2>/dev/null | grep -q wg-watchdog; then
  (crontab -l 2>/dev/null; echo "*/2 * * * * $WATCHDOG_SCRIPT") | crontab -
fi

################################################################################
# 6. FINAL INSTRUCTIONS
################################################################################
echo "-----------------------------------------------------"
echo "[INFO] INSTALLATION COMPLETE!"
echo "-----------------------------------------------------"
echo "1. Server Public Key (for clients to use):"
echo "$SERVER_PUBLIC_KEY"
echo "2. Replace <CLIENT_PUBLIC_KEY> in /etc/wireguard/wg0.conf and in $WATCHDOG_SCRIPT,"
echo "   then restart WireGuard with: wg-quick down wg0 && wg-quick up wg0"
echo "3. On your client (Raspberry Pi), configure wg0.conf with:"
echo "   Endpoint = 209.227.234.177:51820"
echo "   PublicKey = $SERVER_PUBLIC_KEY"
echo "4. Done! If additional NAT is required, UFW is already handling MASQUERADE on enx5."
echo "-----------------------------------------------------"
