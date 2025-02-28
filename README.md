📌 Script Overview

This Bash script configures a Raspberry Pi as:
✅ A Wi-Fi Access Point (AP) on wlan0, allowing devices to connect
✅ A WireGuard VPN client, routing all traffic through a VPS
✅ A NAT gateway, forwarding traffic from the AP through the VPN

This setup allows you to connect a laptop (or other devices) to the Raspberry Pi and have all traffic tunneled through WireGuard.
📖 Setup Instructions

Before running this script, update the following critical parameters:

    WireGuard Private Key (Generated on the Raspberry Pi)
    VPS Public IP Address (209.227.234.177 in this example)
    VPS WireGuard Public Key
    Wi-Fi SSID & Password (Update in /etc/hostapd/hostapd.conf)

To Run the Script:

chmod +x setup_rpi_vpn.sh
sudo ./setup_rpi_vpn.sh

After execution, the Raspberry Pi will automatically reboot.
