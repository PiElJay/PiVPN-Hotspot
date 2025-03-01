📖 Raspberry Pi Wi-Fi Access Point + WireGuard VPN (Full Tunnel)

This project configures a Raspberry Pi as: ✅ A Wi-Fi Access Point (AP) on wlan0, allowing devices to connect.
✅ A WireGuard VPN Client, routing all traffic through a remote VPS.
✅ A NAT Gateway, forwarding all connected devices' traffic through the VPN.

The result? Any device connecting to the Raspberry Pi’s Wi-Fi network will have its traffic routed securely through the VPN, appearing as if browsing from the remote VPS.

📌 Use Cases

This setup is perfect for:

✅ Personal VPN Gateway – A self-hosted, secure VPN for complete control. (Note: Since you use a fixed VPS IP, this does not provide anonymity like Tor or rotating VPN services.)

✅ Remote Work Freedom – Need to appear in another country for work but can’t physically move? Route your traffic through a remote VPS, bypassing restrictions without the "proxy/VPN detected" issues of commercial VPNs like NordVPN.

✅ Bypassing Geo-Restrictions – Access content and services as if you were in another country without relying on centralized VPN providers.

✅ IoT & Home Security – Securely connect smart home devices to a trusted network, even when you're away.

✅ Secure Public Wi-Fi – When traveling, connect to the Raspberry Pi’s Wi-Fi AP and ensure all traffic is encrypted via WireGuard.

✅ Encrypt traffic from untrusted networks (hotels, public Wi-Fi).

🛠 Setup Overview
🔹 Server (VPS) Setup:

    Runs Ubuntu 24.04 (Noble).
    Uses WireGuard VPN to accept client connections.
    Uses UFW (Uncomplicated Firewall) to handle NAT and security.
    Forwards all VPN traffic through the VPS’s internet connection.

🔹 Raspberry Pi Setup:

    Runs Raspberry Pi OS (Bookworm).
    Creates a Wi-Fi Access Point (AP).
    Connects to the VPS via WireGuard VPN.
    Performs NAT forwarding, allowing connected devices to browse securely through the VPN.

🚀 Installation Guide
1️⃣ VPS (WireGuard Server) Setup

On your Ubuntu 24.04 VPS, execute:

wget https://raw.githubusercontent.com/PiElJau/wg_server_setup.sh -O wg_server_setup.sh
chmod +x wg_server_setup.sh
sudo ./wg_server_setup.sh

➡️ Important Notes for the VPS:

📌 The script will:

    Install WireGuard & UFW.
    Configure NAT & IP forwarding.
    Generate WireGuard keys.
    Create a default WireGuard config (/etc/wireguard/wg0.conf).
    Start WireGuard and enable a watchdog to monitor connections.
    
IMPORTANT:
🔑 After completion, note the VPS Public Key (displayed at the end of the script).
You'll need this when configuring the Raspberry Pi.
---------
2️⃣ Raspberry Pi (Client + AP) Setup

On your Raspberry Pi, execute:

wget https://raw.githubusercontent.com/PiElJay/setup_rpi_vpn.sh -O setup_rpi_vpn.sh
chmod +x setup_rpi_vpn.sh
sudo ./setup_rpi_vpn.sh

➡️ Important Notes for the Raspberry Pi:

📌 The script will:

    Set up a Wi-Fi Access Point using hostapd & dnsmasq.
    Install WireGuard and configure it to connect to the VPS.
    Enable IP forwarding & NAT, so connected devices can browse through the VPN.
    Persist firewall rules using iptables-persistent.
    Enable a watchdog to restart WireGuard if the connection drops.

⚙️ Configuration Details
📌 WireGuard Configurations
🔹 VPS (/etc/wireguard/wg0.conf on the server)

Replace <CLIENT_PUBLIC_KEY> with the key from the Raspberry Pi:

[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <SERVER_PRIVATE_KEY>

[Peer]
PublicKey = <CLIENT_PUBLIC_KEY>
AllowedIPs = 10.0.0.2/32

🔹 Raspberry Pi (/etc/wireguard/wg0.conf on the Pi)

Replace <SERVER_PUBLIC_KEY> and <VPS_IP>:

[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address = 10.0.0.2/24
DNS = 8.8.8.8

[Peer]
PublicKey = <SERVER_PUBLIC_KEY>
Endpoint = <VPS_IP>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25

📡 Wi-Fi Access Point Configuration

The Raspberry Pi’s Wi-Fi AP settings are stored in:

    SSID & Password: /etc/hostapd/hostapd.conf
    DHCP & DNS settings: /etc/dnsmasq.conf

To change the Wi-Fi name (SSID) and password, edit:

sudo nano /etc/hostapd/hostapd.conf

Example:

ssid=SecureVPN-WiFi
wpa_passphrase=MyStrongPassword!

Save and restart:

sudo systemctl restart hostapd

📌 Firewall & NAT Configuration

Both VPS & Raspberry Pi use NAT (Masquerading) to forward traffic.
🔹 VPS Firewall (UFW)

Run:

sudo ufw status verbose

Expected output:

To                         Action      From
--                         ------      ----
51820/udp                  ALLOW       Anywhere
22/tcp                     ALLOW       Anywhere

🔹 Raspberry Pi Firewall (iptables)

Check:

sudo iptables -t nat -L -v

Expected rules:

Chain POSTROUTING (policy ACCEPT)
 pkts bytes target     prot opt in  out   source          destination
 0     0 MASQUERADE  all  --  any  eth0  10.0.0.0/24     anywhere
 0     0 MASQUERADE  all  --  any  eth0  192.168.50.0/24 anywhere

🔍 Troubleshooting
❌ No Internet on Connected Devices?

1️⃣ Check IP Forwarding:

sysctl net.ipv4.ip_forward

If it's 0, enable it:

echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ip_forward.conf
sysctl --system

2️⃣ Verify VPN Connection on the Raspberry Pi:

wg show

Should display a handshake.

3️⃣ Check NAT Rules:

iptables -t nat -L -v

Ensure POSTROUTING MASQUERADE is applied.
🎯 Next Steps

🔹 Enhance security: Change the Wi-Fi password (hostapd.conf).
🔹 Add more clients: Add more [Peer] sections in the VPS wg0.conf.
🔹 Monitor VPN uptime: Use wg-watchdog to auto-restart WireGuard.
📜 License

📌 MIT License – Feel free to modify, distribute, and improve!
📢 Credits

    WireGuard: Lightweight and secure VPN technology.
    Raspberry Pi Foundation: For the amazing Raspberry Pi ecosystem.
    UFW (Uncomplicated Firewall): Simple yet powerful firewall tool.

🎉 Enjoy Secure Browsing via Your Own VPN Access Point! 🚀
🔗 GitHub Repository Link:
https://github.com/PiElJay/Tunnel-Gateway

🌍 Global Impact

If you like it, give it a ⭐ on GitHub! 🚀
Found an issue? Open an issue or PR to improve it!
This is basilar script, it must need to be improved on security
