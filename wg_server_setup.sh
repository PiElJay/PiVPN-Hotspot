#!/usr/bin/env bash
# WireGuard automated installer – Ubuntu 24.04 (Noble)
# Author: PiEljay
# Version: 1.2 – 2025-05-22
set -euo pipefail
IFS=$'\n\t'

###############################################################################
#                              Utility functions                              #
###############################################################################
die() { echo "[FATAL] $*" >&2; exit 1; }

confirm() {
  local msg=$1
  local yn
  read -rp "$msg [y/N] " yn
  [[ ${yn,,} == y ]]
}

prompt() {
  # $1 = var name, $2 = prompt, $3 = default, $4 = regex validator
  local __var=$1 question=$2 def=$3 re=${4:-'.+'} val
  while true; do
    read -rp "$question [$def]: " val
    val=${val:-$def}
    [[ $val =~ $re ]] || { echo "Invalid format."; continue; }
    confirm "You entered '$val'. Confirm?" && break
  done
  printf -v "$__var" %s "$val"
}

backup() { local f=$1; cp -a "$f" "${f}.bak.$(date +%s)"; }

cleanup() {
  echo "[WARN] Aborted – rolling back."
  [[ -f "$UFW_BEFORE".backup ]] && mv "$UFW_BEFORE".backup "$UFW_BEFORE"
  systemctl is-active --quiet wg-quick@wg0 && wg-quick down wg0 || true
}
trap cleanup ERR INT

###############################################################################
#                           Interactive parameter set                         #
###############################################################################
echo "=== WireGuard server quick-installer ==="

prompt EXT_IF   "External network interface"               "$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++)if($i=="dev")print $(i+1); exit}')" '^[a-zA-Z0-9]+$'
prompt PUBLIC_IP "Public IPv4 address of this host"         "$(curl -s https://api64.ipify.org)"            '^[0-9.]+$'
prompt WG_PORT   "UDP port to listen on"                    "51820"                                         '^[0-9]{1,5}$'
prompt WG_ADDR4  "Server VPN address (CIDR)"                "10.0.0.1/24"                                   '^[0-9./]+$'
prompt WG_ADDR6  "Add IPv6 subnet? (empty to skip)"         ""                                              '^([a-fA-F0-9:/]+(/[0-9]{1,3})?)?$'
ENABLE_IPV6=false; [[ -n $WG_ADDR6 ]] && ENABLE_IPV6=true
prompt PEER_KEY  "First peer public key (can add later)"    ""                                              '^([A-Za-z0-9+/]{43}=)?$'

echo
confirm "Proceed with installation?" || die "Cancelled by user."

###############################################################################
#                         Package installation & update                       #
###############################################################################
echo "[INFO] Updating packages..."
apt update -y
apt install -y wireguard wireguard-tools ufw curl

###############################################################################
#                              Sysctl & firewall                              #
###############################################################################
echo "[INFO] Enabling IP forwarding..."
sysctl_flags=(
  "net.ipv4.ip_forward=1"
)
$ENABLE_IPV6 && sysctl_flags+=("net.ipv6.conf.all.forwarding=1")
for s in "${sysctl_flags[@]}"; do
  grep -q "^$s" /etc/sysctl.conf || echo "$s" >> /etc/sysctl.conf
done
sysctl -p

echo "[INFO] Configuring UFW..."
ufw allow 22/tcp
ufw allow "${WG_PORT}"/udp
ufw --force enable

UFW_BEFORE="/etc/ufw/before.rules"
backup "$UFW_BEFORE"; mv "$UFW_BEFORE" "$UFW_BEFORE".backup

# Extract network part for NAT rule
WG_NETWORK=$(echo "$WG_ADDR4" | cut -d'/' -f1 | sed 's/\.[0-9]*$/\.0/')

cat > "$UFW_BEFORE" <<EOF
# START WireGuard NAT section
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s $WG_NETWORK/24 -o $EXT_IF -j MASQUERADE
COMMIT
# END WireGuard NAT section
$(cat "$UFW_BEFORE".backup)
EOF

# Reload UFW to apply NAT rules
ufw reload

# Allow routed traffic back out
ufw route allow in on wg0 out on "$EXT_IF" to any
$ENABLE_IPV6 && ufw route allow in on wg0 out on "$EXT_IF" to any proto ipv6

###############################################################################
#                              Key generation                                 #
###############################################################################
echo "[INFO] Generating server keypair..."
install -o root -g root -m 700 -d /etc/wireguard
cd /etc/wireguard
umask 077
SERVER_PRIV=$(wg genkey)
SERVER_PUB=$(sed 's/$/\n/' <<<"$SERVER_PRIV" | wg pubkey)

###############################################################################
#                           Write wg0.conf safely                             #
###############################################################################
echo "[INFO] Creating wg0.conf..."

# Extract network prefix more robustly
WG_NET_PREFIX=$(echo "$WG_ADDR4" | cut -d'/' -f1 | sed 's/\.[0-9]*$//')

cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = $WG_ADDR4${ENABLE_IPV6:+,$WG_ADDR6}
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV
SaveConfig = true

# First peer (optional)
$( [[ -n $PEER_KEY ]] && cat <<PEER
[Peer]
PublicKey = $PEER_KEY
AllowedIPs = ${WG_NET_PREFIX}.2/32${ENABLE_IPV6:+,${WG_ADDR6%::*}::2/128}
PersistentKeepalive = 25
PEER
)
EOF
chmod 600 /etc/wireguard/wg0.conf

###############################################################################
#                    Enable service & persistent watchdog                     #
###############################################################################
systemctl enable --now wg-quick@wg0

cat > /etc/systemd/system/wg-watchdog.service <<EOF
[Unit]
Description=WireGuard handshake watchdog
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wg-watchdog
EOF

cat > /etc/systemd/system/wg-watchdog.timer <<EOF
[Unit]
Description=Run WireGuard watchdog every 2 min

[Timer]
OnBootSec=5min
OnUnitActiveSec=2min
Unit=wg-watchdog.service

[Install]
WantedBy=timers.target
EOF

cat > /usr/local/bin/wg-watchdog <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Get current timestamp
NOW=$(date +%s)
# Check for peers with no handshake in last 120 seconds
wg show wg0 dump | tail -n +2 | while read -r line; do
  PEER=$(echo "$line" | cut -f1)
  HANDSHAKE=$(echo "$line" | cut -f5)
  if [[ $HANDSHAKE -eq 0 ]] || [[ $((NOW - HANDSHAKE)) -gt 120 ]]; then
    logger -t "wg-watchdog" -p notice "peer $PEER down >120s, removing"
    wg set wg0 peer "$PEER" remove
  fi
done
EOF
chmod +x /usr/local/bin/wg-watchdog
systemctl daemon-reload
systemctl enable --now wg-watchdog.timer

###############################################################################
#                                   Output                                    #
###############################################################################
cat <<EOF

========================================================
        WireGuard installation complete
========================================================
Server public key : $SERVER_PUB
Config file       : /etc/wireguard/wg0.conf
Watchdog          : systemd timer (wg-watchdog.timer)
Note: SaveConfig=true means runtime changes auto-save to wg0.conf
Add a new client  : sudo wg genkey | tee /etc/wireguard/<name>.priv | wg pubkey > /etc/wireguard/<name>.pub
Then run          : sudo wg set wg0 peer <client_pub> allowed-ips <next_IP>/32
========================================================
EOF
