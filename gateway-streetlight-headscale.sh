#!/bin/sh
# ---------------------------------------------------------
# RAK7289 Headscale / Tailscale auto setup
# - Uses EUI as hostname (from MAC -> EUI64)
# - Registers to self-hosted Headscale
# - Advertises RAK LAN subnet 192.168.230.0/24
# - No exit node, only subnet routing
# ---------------------------------------------------------

# ---------------------------------------------------------
#         Created BY = HAZIQ
# ---------------------------------------------------------

set -e

### 🔧 EDIT THESE VALUES ###
HEADSCALE_URL="https://hs.client.loranet.my"
AUTHKEY="a1cafb62710fb075a66ed85f01e79796a28910432f5f160d"      # <-- put your preauth key here
SUBNET_CIDR="192.168.230.0/24"           # RAK7289 default LAN
HOST_PREFIX="rak7289"                    # prefix for hostname
##########################################

echo "=== RAK7289 Headscale auto-setup ==="

# --- Detect package manager (RAK is usually OpenWrt/opkg) ---
if command -v opkg >/dev/null 2>&1; then
    echo "[*] Detected OpenWrt/opkg system"

    echo "[*] Installing Tailscale (if not installed)..."
    opkg update
    opkg install tailscale tailscaled || true

    echo "[*] Enabling tailscaled service..."
    /etc/init.d/tailscaled enable || true
    /etc/init.d/tailscaled start || true

elif command -v apt >/dev/null 2>&1; then
    echo "[*] Detected Debian/Ubuntu-style system"

    echo "[*] Installing Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh

    echo "[*] Enabling tailscaled service..."
    systemctl enable tailscaled || true
    systemctl start tailscaled || true
else
    echo "[!] Could not detect supported package manager (opkg/apt)."
    echo "    Install Tailscale manually, then re-run this script."
    exit 1
fi

# --- Enable IPv4 forwarding (needed for subnet routing) ---
echo "[*] Enabling IPv4 forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
if [ -f /etc/sysctl.conf ]; then
    grep -q "net.ipv4.ip_forward" /etc/sysctl.conf 2>/dev/null || \
        echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

# --- Find a MAC address to derive EUI from ---
echo "[*] Detecting base interface MAC for EUI..."
MAC_IFACE=""
for IF in eth0 eth1 br-lan; do
    if [ -e "/sys/class/net/$IF/address" ]; then
        MAC_IFACE="$IF"
        break
    fi
done

if [ -z "$MAC_IFACE" ]; then
    echo "[!] Could not find a suitable interface (eth0/eth1/br-lan)."
    echo "    Please adjust the script to use the correct interface."
    exit 1
fi

MAC=$(cat /sys/class/net/$MAC_IFACE/address)
echo "[*] Using interface: $MAC_IFACE (MAC: $MAC)"

# --- Convert MAC xx:xx:xx:xx:xx:xx -> EUI64 XXYYZZFFFEAABBCC ---
MAC_NO_COLON=$(echo "$MAC" | tr -d ':')
OUI=${MAC_NO_COLON%??????}   # first 6 hex chars
NIC=${MAC_NO_COLON#??????}   # last 6 hex chars
EUI_RAW="${OUI}FFFE${NIC}"
EUI=$(echo "$EUI_RAW" | tr 'a-f' 'A-F')

echo "[*] Derived EUI: $EUI"

# --- Build hostname based on EUI ---
TS_HOSTNAME="${HOST_PREFIX}-${EUI}"
echo "[*] Tailscale hostname will be: ${TS_HOSTNAME}"

# Try to set system hostname (non-fatal if it fails)
if command -v hostnamectl >/dev/null 2>&1; then
    hostnamectl set-hostname "${TS_HOSTNAME}" || true
else
    echo "${TS_HOSTNAME}" > /proc/sys/kernel/hostname 2>/dev/null || true
fi

# --- Bring Tailscale up with Headscale + subnet route ---
if [ "$AUTHKEY" = "a1cafb62710fb075a66ed85f01e79796a28910432f5f160d" ]; then
    echo "[!] You did NOT set AUTHKEY in this script."
    echo "    Edit the script and put your Headscale preauth key in AUTHKEY."
    exit 1
fi

echo "[*] Bringing Tailscale up against Headscale..."
tailscale up \
  --login-server="${HEADSCALE_URL}" \
  --authkey="${AUTHKEY}" \
  --hostname="${TS_HOSTNAME}" \
  --advertise-routes="${SUBNET_CIDR}" \
  --accept-routes=true \
  --accept-dns=false

RC=$?
if [ $RC -ne 0 ]; then
    echo "[!] tailscale up failed with exit code $RC"
    exit $RC
fi

echo ""
echo "=== DONE ==="
echo "RAK7289 is now registered to Headscale and advertising ${SUBNET_CIDR}"
echo "Check / enable the route in Headscale UI:"
echo "  https://hs-ui.client.loranet.my/web/devices.html"
echo ""
echo "This node hostname in Headscale: ${TS_HOSTNAME}"
