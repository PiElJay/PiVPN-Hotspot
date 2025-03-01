📖 Raspberry Pi Wi-Fi Access Point + WireGuard VPN (Full Tunnel)
🔹 Overview

This project turns a Raspberry Pi into:
✅ A Wi-Fi Access Point (AP) on wlan0, allowing devices to connect.
✅ A WireGuard VPN Client, routing all traffic through a remote VPS.
✅ A NAT Gateway, forwarding all connected devices' traffic through the VPN.

🌍 The result?
Any device connecting to the Raspberry Pi’s Wi-Fi network will have its traffic routed securely through the VPN, appearing as if browsing from the remote VPS.
📌 Use Cases

This setup is perfect for:

✅ 📡 Personal VPN Gateway – A self-hosted VPN for privacy & control (Note: Since you use a fixed VPS IP, this does not provide anonymity like Tor or rotating VPN services.)

✅ 🌍 Remote Work Freedom – Need to appear in another country for work but can’t physically move? Route your traffic through a remote VPS, bypassing restrictions without VPN/proxy detection issues.

✅ 🎥 Bypassing Geo-Restrictions – Access region-locked content as if you were in another country, without relying on commercial VPN providers.

✅ 🏠 IoT & Home Security – Securely connect smart home devices to a trusted network, even when you’re away.

✅ 🚀 Secure Public Wi-Fi – When traveling, connect to the Raspberry Pi’s Wi-Fi AP and ensure all traffic is encrypted via WireGuard.

✅ 🔒 Encrypt traffic from untrusted networks – Secure browsing on hotels, airports, and public Wi-Fi.
🛠 Setup Overview
🔹 Server (VPS)

✅ OS: Ubuntu 24.04 (Noble)
✅ Technologies: WireGuard, UFW
✅ Functionality:

    Accepts WireGuard client connections
    Routes all VPN traffic through the VPS’s Internet
    Enables NAT & forwarding

🔹 Raspberry Pi

✅ OS: Raspberry Pi OS (Bookworm)
✅ Technologies: WireGuard, Hostapd, Dnsmasq, iptables
✅ Functionality:

    Creates a Wi-Fi Access Point
    Connects all traffic through WireGuard VPN
    Enables NAT forwarding for connected devices

🚀 Installation Guide
1️⃣ VPS (WireGuard Server) Setup

On your Ubuntu 24.04 VPS, execute:

wget https://raw.githubusercontent.com/PiElJay/wg_server_setup.sh -O wg_server_setup.sh
chmod +x wg_server_setup.sh
sudo ./wg_server_setup.sh

➡️ The script will automatically:
✅ Install WireGuard & UFW
✅ Enable NAT & IP forwarding
✅ Generate WireGuard keys
✅ Create /etc/wireguard/wg0.conf
✅ Start WireGuard and set up a watchdog to monitor connections

🔑 At the end of the installation, copy the VPS Public Key!
You’ll need this when configuring the Raspberry Pi.
2️⃣ Raspberry Pi (Client + AP) Setup

On your Raspberry Pi, execute:

wget https://raw.githubusercontent.com/PiElJay/setup_rpi_vpn.sh -O setup_rpi_vpn.sh
chmod +x setup_rpi_vpn.sh
sudo ./setup_rpi_vpn.sh

👉 🔹 The setup is now INTERACTIVE!
The script will prompt you to enter:
✅ WireGuard Server Public Key
✅ WireGuard Server IP (e.g., 209.227.234.177:51820)
✅ VPN Subnet (default: 10.0.0.0/24)
✅ Wi-Fi SSID & Password

📌 The setup process includes:
✅ Creating a Wi-Fi Access Point using Hostapd & Dnsmasq
✅ Installing WireGuard and configuring the VPN connection
✅ Enabling IP forwarding & NAT
✅ Persisting iptables rules (to survive reboots)
✅ Setting up a VPN watchdog to ensure the tunnel stays up
⚙️ Configuration Details
📌 🔹 WireGuard Configuration
VPS (/etc/wireguard/wg0.conf)

    IMPORTANT: Replace <CLIENT_PUBLIC_KEY> with the key from the Raspberry Pi.

[Interface]
Address = 10.0.0.1/24
ListenPort = 51820
PrivateKey = <SERVER_PRIVATE_KEY>

[Peer]
PublicKey = <CLIENT_PUBLIC_KEY>
AllowedIPs = 10.0.0.2/32

Raspberry Pi (/etc/wireguard/wg0.conf)

    IMPORTANT: Replace <SERVER_PUBLIC_KEY> and <VPS_IP>.

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

🔹 SSID & Password: /etc/hostapd/hostapd.conf
🔹 DHCP & DNS Settings: /etc/dnsmasq.conf

👉 To change the Wi-Fi name and password:

sudo nano /etc/hostapd/hostapd.conf

Modify:

ssid=SecureVPN-WiFi
wpa_passphrase=MyStrongPassword!

Restart:

sudo systemctl restart hostapd

📌 Firewall & NAT Configuration
🔹 VPS Firewall (UFW)

sudo ufw status verbose

Expected output:

To                         Action      From
--                         ------      ----
51820/udp                  ALLOW       Anywhere
22/tcp                     ALLOW       Anywhere

🔹 Raspberry Pi Firewall (iptables)

sudo iptables -t nat -L -v

Expected output:

Chain POSTROUTING (policy ACCEPT)
 pkts bytes target     prot opt in  out   source          destination
 0     0 MASQUERADE  all  --  any  eth0  10.0.0.0/24     anywhere
 0     0 MASQUERADE  all  --  any  eth0  192.168.50.0/24 anywhere

🔍 Troubleshooting

❌ No Internet on Connected Devices?

1️⃣ Check IP Forwarding:

sysctl net.ipv4.ip_forward

If it’s 0, enable it:

echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ip_forward.conf
sysctl --system

2️⃣ Verify VPN Connection on the Raspberry Pi:

wg show

You should see an active handshake.

3️⃣ Check NAT Rules:

iptables -t nat -L -v

Ensure POSTROUTING MASQUERADE is applied.
🎯 Next Steps

✅ Enhance Security – Change the Wi-Fi password in hostapd.conf.
✅ Add More Clients – Add new [Peer] sections in the VPS wg0.conf.
✅ Monitor VPN Uptime – Use the wg-watchdog script to restart WireGuard if it disconnects.

📜 MIT License – Feel free to modify and distribute!
🌍 If this helped, give it a ⭐ on GitHub! 🚀
🔗 GitHub Repository
