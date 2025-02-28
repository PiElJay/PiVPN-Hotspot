📌 Raspberry Pi - WiFi Access Point & WireGuard VPN Gateway
🚀 Overview

This script transforms a Raspberry Pi into a secure, self-hosted Wi-Fi access point that routes all connected devices' traffic through a WireGuard VPN tunnel.

🔹 Key Features:
✅ Wi-Fi Access Point (AP) on wlan0, allowing devices to connect
✅ WireGuard VPN Client, routing all outgoing traffic via a VPS
✅ NAT Gateway, forwarding traffic from connected devices through the VPN
✅ Automatic VPN Failover, with a watchdog script to restart WireGuard if it fails

This setup is perfect for situations where you want to:

    Secure your internet traffic while using public Wi-Fi
    Bypass geo-restrictions by routing traffic through your VPS
    Provide VPN access to all devices without setting up VPN clients on each one

📖 Setup Instructions
1️⃣ Prerequisites

Before running the script, ensure:

    Your Raspberry Pi is running Raspberry Pi OS (Debian-based)
    You are connected via Ethernet (eth0), as wlan0 will become the Access Point
    You have a WireGuard VPN set up on a VPS (Ubuntu/Debian recommended)

2️⃣ Update the Configuration

Before executing the script, update the following critical parameters inside /etc/wireguard/wg0.conf:
Parameter	Description	Example
PrivateKey	Raspberry Pi’s WireGuard private key	(Generated on the Pi)
PublicKey	VPS WireGuard public key	/HNPw2YYc9QuRV...TQ4=
Endpoint	VPS Public IP + WireGuard Port	209.227.234.177:51820
AllowedIPs	Route all traffic through VPN	0.0.0.0/0
DNS	VPN's DNS server (Google in this case)	8.8.8.8
3️⃣ Run the Script

    Clone or Download the script:

git clone https://github.com/yourusername/rpi-vpn-ap.git
cd rpi-vpn-ap

Make it executable and run it as root:

    chmod +x setup_rpi_vpn.sh
    sudo ./setup_rpi_vpn.sh

    The script will:
        Update the system and install required packages
        Configure Wi-Fi AP & DHCP using hostapd and dnsmasq
        Enable IP forwarding & configure iptables for proper routing
        Set up and enable WireGuard
        Deploy a VPN watchdog to auto-restart the VPN if it fails

    After execution, the Raspberry Pi will automatically reboot.

📡 How to Connect to the Wi-Fi Access Point

    SSID: MySecureAP (Change in /etc/hostapd/hostapd.conf)
    Password: ChangeThisPassword!
    DHCP Range: 192.168.50.10 - 192.168.50.150

Once connected, all traffic will be routed securely through the VPN.
🛠 Troubleshooting

1️⃣ Check VPN Status

systemctl status wg-quick@wg0
journalctl -u wg-quick@wg0 --no-pager | tail -20

2️⃣ Check IP Forwarding

sysctl net.ipv4.ip_forward

✔ Output should be: net.ipv4.ip_forward = 1

3️⃣ Verify iptables NAT Rules

iptables -t nat -L -v

4️⃣ Test VPN Connectivity

curl -4 ifconfig.me

✔ If this shows your VPS IP, the VPN is working correctly.
📌 Notes & Customization

    Change the Wi-Fi SSID & password inside /etc/hostapd/hostapd.conf
    If using a different VPN provider, adjust WireGuard settings in /etc/wireguard/wg0.conf
    To disable the VPN failover script, remove the cron job with:

    crontab -e

    and delete the line with vpn-watchdog

📜 Credits & License

Developed by [Your Name] - Feel free to contribute and improve! 🚀
Licensed under MIT License – Open-source and free to use.

Now you have a plug-and-play Raspberry Pi VPN Access Point! 🎉 🔥
Let me know if you need any final tweaks! 🚀
