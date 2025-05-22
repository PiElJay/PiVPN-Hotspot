# 🍓 Raspberry Pi Wi-Fi Access Point + WireGuard VPN (Full Tunnel)  

---

## 📌 Overview  

This project turns a Raspberry Pi into:  

✅ **A Wi-Fi Access Point** (`wlan0`), letting nearby devices connect.  
✅ **A WireGuard VPN Client**, sending all traffic to a remote VPS.  
✅ **A NAT Gateway**, so every Wi-Fi client’s traffic is tunneled.  

🔹 **The result?**  
Any device that joins the Pi’s network browses the Internet **as if it were sitting behind the VPS**.

---

## 📌 Use Cases  

| ✅ | Scenario | Why it rocks |
|----|----------|-------------|
| ✔️ | **Personal VPN gateway** | Keep full control of keys & logs (note: fixed VPS IP ≠ anonymity like Tor). |
| ✔️ | **Remote-work freedom** | Appear in another country without commercial VPN fingerprints. |
| ✔️ | **Geo-unblocking** | Stream region-locked content from home or travelling. |
| ✔️ | **IoT & home security** | Route smart-home gear through a trusted egress. |
| ✔️ | **Public-Wi-Fi armour** | Tunnel safely in hotels, airports & cafés. |

---

## ⚙️ Setup Overview  

### 🔹 Server (VPS)  
* **OS:** Ubuntu 24.04 (Noble)  
* **Tech:** WireGuard, UFW  
* **Role:**  
  * Accept VPN clients  
  * NAT **wg0 → `<EXT_IF>`**  
  * Forward traffic to the Internet  

### 🔹 Raspberry Pi  
* **OS:** Raspberry Pi OS (Bookworm)  
* **Tech:** WireGuard, Hostapd, Dnsmasq, **iptables-persistent (via netfilter-persistent), chrony**  
* **Role:**  
  * Create the Wi-Fi AP  
  * NAT **LAN → wg0**  
  * Tunnel everything through the VPS  

Wi-Fi clients ─► wlan0 ─► NAT ─► wg0 (Pi) ────────────► wg0 (VPS) ─► NAT ─► Internet
🔒 🔒


---

## 🚀 Installation Guide  

### 1️⃣ VPS (WireGuard Server)  

```bash
wget https://raw.githubusercontent.com/PiElJay/Tunnel-Gateway/refs/heads/main/wg_server_setup.sh -O wg_server_install.sh
chmod +x wg_server_install.sh
sudo ./wg_server_install.sh

🔹 What the script does
✅ Installs WireGuard & UFW
✅ Enables NAT & IP-forwarding
✅ Generates server keys and /etc/wireguard/wg0.conf
✅ Starts wg-quick@wg0 and a handshake-watchdog (systemd timer)

📢 Note the VPS public key printed at the end—you’ll need it for the Pi.
2️⃣ Raspberry Pi (Client + AP)

wget https://raw.githubusercontent.com/PiElJay/Tunnel-Gateway/refs/heads/main/setup_rpi_vpn.sh -O setup_rpi_vpn.sh
chmod +x setup_rpi_vpn.sh
sudo ./setup_rpi_vpn.sh

🔹 What the script does
✅ Builds a Wi-Fi AP with hostapd & dnsmasq
✅ Generates client keys and connects to the VPS via WireGuard
✅ Enables IP-forwarding & NAT (persisted with iptables-persistent)
✅ Uses systemd-restart semantics—no separate watchdog needed 🎉
🔗 Parameter Cross-Check (don’t mix these up!)
VPS installer prompt	Pi installer prompt	Value that must match
Public IPv4 / DNS	part of WG_ENDPOINT	VPS address
UDP port (WG_PORT)	WG_ENDPOINT suffix	e.g. 51820
Server VPN network (WG_ADDR4, default 10.0.0.1/24)	VPN_SUBNET (10.0.0.0/24)	Same /24
Optional first peer pubkey	auto-generated CLIENT_PUB	Paste into VPS (now or later)
⚙️ Configuration Details
📄 WireGuard – server (/etc/wireguard/wg0.conf)

[Interface]
Address     = 10.0.0.1/24
ListenPort  = 51820
PrivateKey  = <SERVER_PRIVATE_KEY>
SaveConfig  = true   # default in the script

[Peer]
PublicKey   = <CLIENT_PUBLIC_KEY>
AllowedIPs  = 10.0.0.2/32
PersistentKeepalive = 25

📄 WireGuard – Raspberry Pi (/etc/wireguard/wg0.conf)

[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address    = 10.0.0.2/24
DNS        = 9.9.9.9

[Peer]
PublicKey  = <SERVER_PUBLIC_KEY>
Endpoint   = <VPS_IP>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25

📡 Wi-Fi AP

    SSID & password: /etc/hostapd/hostapd.conf

    DHCP & DNS: /etc/dnsmasq.conf

sudo nano /etc/hostapd/hostapd.conf   # edit ssid= / wpa_passphrase=
sudo systemctl restart hostapd

🔥 Firewall & NAT
🔹 VPS (UFW)

sudo ufw status verbose

Expected rules:

51820/udp        ALLOW Anywhere
22/tcp           ALLOW Anywhere
wg0 on <ext_if>  ALLOW FWD  (route rule)

🔹 Raspberry Pi (iptables)

sudo iptables -t nat -L POSTROUTING -v -n

Expected (out-iface usually wg0):

Chain POSTROUTING (policy ACCEPT)
pkts bytes target     prot opt in  out source            destination
12   860  MASQUERADE  all  --  any wg0  192.168.50.0/24  anywhere

    Why two MASQUERADES?

        Pi: LAN → wg0 so Wi-Fi clients share one VPN IP.

        VPS: wg0 → EXT_IF so all peer traffic exits with the VPS public IP.

🔍 Troubleshooting
❌ Symptom	Check	Fix
No Internet for Wi-Fi clients	sysctl net.ipv4.ip_forward → should be 1	echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ip_forward.conf && sysctl --system
No handshake visible	wg show on Pi & VPS	open UDP port in cloud firewall; verify keys & subnet match
NAT rule missing	iptables -t nat -L POSTROUTING -v -n	Ensure a MASQUERADE rule exists and the OUT iface matches wg0 (or the default route)
🎯 Next Steps

🔹 Security hardening: rotate the Wi-Fi passphrase regularly.
🔹 Add more peers:

# on VPS
sudo wg set wg0 peer <NEW_PUB> allowed-ips 10.0.0.<N>/32
# with SaveConfig=true the change persists automatically 🎉

🔹 Monitoring: the VPS watchdog timer prunes dead peers automatically.
📜 License

📌 MIT License – hack, share and enjoy!
📢 Credits

    WireGuard – the lean, modern VPN.

    Raspberry Pi Foundation – for the tiny powerhouse.

    ✨ LLMs (ChatGPT, DeepSeek) helped refine these scripts.


---

## TL;DR - Quick Start & Key Info

This project turns a Raspberry Pi into a Wi-Fi Access Point that tunnels all its traffic through a WireGuard VPN on your own VPS. Any device connecting to the Pi's Wi-Fi will appear to be Browse from the VPS's location.

### 🚀 What it Does:

* **VPS:** Acts as a WireGuard VPN server.
* **Raspberry Pi:**
    1.  Connects to your VPS as a WireGuard client.
    2.  Creates a new Wi-Fi network (Access Point).
    3.  Routes all traffic from connected Wi-Fi devices through the VPN.

### 🛠️ How to Install (Super Basic):

1.  **On your VPS (Ubuntu 24.04):**
    ```bash
    wget https://raw.githubusercontent.com/PiElJay/Tunnel-Gateway/refs/heads/main/wg_server_setup.sh -O wg_server_install.sh
    chmod +x wg_server_install.sh
    sudo ./wg_server_install.sh
    ```
    * **Note the `Server public key` output at the end.**

2.  **On your Raspberry Pi (Raspberry Pi OS Bookworm):**
    ```bash
    wget https://raw.githubusercontent.com/PiElJay/Tunnel-Gateway/refs/heads/main/setup_rpi_vpn.sh -O setup_rpi_vpn.sh
    chmod +x setup_rpi_vpn.sh
    sudo ./setup_rpi_vpn.sh
    ```
    * You'll need the `Server public key` from the VPS step.
    * **Note the `Client public key` output at the end.**

3.  **Back on your VPS:**
    * Add the Raspberry Pi's `Client public key` and its assigned VPN IP (e.g., `10.0.0.2/32` if using defaults) to the server's WireGuard configuration:
        ```bash
        sudo wg set wg0 peer <PI_CLIENT_PUBLIC_KEY> allowed-ips <PI_VPN_IP>/32
        ```
        (The Pi script output will remind you of this command with the correct key and IP).

### 📝 Key Things to Note & Input:

* **Parameter Cross-Check:** Pay close attention to the "Parameter Cross-Check" table in the main README to ensure VPN settings match between VPS and Pi.
* **Public Keys:**
    * The VPS script outputs a **Server Public Key**. You'll need to input this into the Raspberry Pi script.
    * The Raspberry Pi script outputs a **Client Public Key**. You'll need to add this to the VPS WireGuard configuration.
* **Script Inputs:** The installation scripts will ask you for the following:

    * **For `wg_server_install.sh` (VPS):**
        * `External network interface` (e.g., `eth0`)
        * `Public IPv4 address` of the VPS
        * `UDP port` for WireGuard (default: `51820`)
        * `Server VPN address (CIDR)` (default: `10.0.0.1/24`)
        * Optional: `IPv6 subnet`
        * Optional: `First peer public key` (you can add the Pi's key here if you run the Pi script first, or add it later)

    * **For `setup_rpi_vpn.sh` (Raspberry Pi):**
        * `WireGuard server public key` (from VPS script output)
        * `WireGuard server endpoint (IP:port)` (e.g., `YOUR_VPS_IP:51820`)
        * `VPN subnet (CIDR)` (must match server's, e.g., `10.0.0.0/24`)
        * `Wi-Fi SSID` (your new Wi-Fi network name)
        * `Wi-Fi password` (for your new Wi-Fi)
        * `Country code` (for Wi-Fi regulations, e.g., `US`, `GB`, `FR`)
        * `Wi-Fi channel`
        * `AP IP address` (Pi's IP on the new Wi-Fi LAN, e.g., `192.168.50.1`)

* **Reboot Pi:** A reboot of the Raspberry Pi is recommended after its setup script completes.

🔥 If you like it, give the repo a small ⭐, if you don't like it give it anyway ! ```

[Risitas](https://media1.giphy.com/media/v1.Y2lkPTc5MGI3NjExb3pwOGJjM25ya3VzMzM5azgxMmtvY2ZqYndkMGVrYWs4cHNuNDJoNSZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/frGReyWTKNZVHmzh2p/giphy.gif)
