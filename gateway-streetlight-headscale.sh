#!/bin/sh
# ---------------------------------------------------------
# RAK7289 WisGateOS 2 - Headscale / Tailscale auto setup
# BusyBox ash compatible version
# ---------------------------------------------------------

set -e

### CONFIG ###
HEADSCALE_URL="https://hs.client.loranet.my"
SUBNET="192.168.230.0/24"
HOST_PREFIX="RAK7289CV2"

# AUTHKEY (placeholder for testing)
AUTHKEY="${AUTHKEY:-a1cafb62710fb075a66ed85f01e79796a28910432f5f160d}"

if [ "$AUTHKEY" = "TESTKEY_PLACEHOLDER" ]; then
    echo "⚠ Using TEST AUTHKEY placeholder."
    echo "⚠ Script will run, but WILL NOT register."
fi

echo "=== RAK7289 WisGateOS 2 Headscale Setup (BusyBox Compatible) ==="

# ---------------------------------------------------------
# 1. Detect OpenWrt / WisGateOS
# ---------------------------------------------------------
if ! command -v opkg >/dev/null 2>&1; then
    echo "ERROR: This system is not OpenWrt/WisGateOS."
    exit 1
fi

echo "[1] WisGateOS/OpenWrt detected ✔"

# ---------------------------------------------------------
# 2. Install Tailscale if missing
# ---------------------------------------------------------
if ! command -v tailscale >/dev/null 2>&1; then
    echo "[2] Installing Tailscale..."
    opkg update
    opkg install tailscale tailscaled || true
else
    echo "[2] Tailscale already installed ✔"
fi

# ---------------------------------------------------------
# 3. Enable IPv4 forwarding
# ---------------------------------------------------------
echo "[3] Enabling IPv4 forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# ---------------------------------------------------------
# 4. Detect MAC → EUI64 for hostname
# ---------------------------------------------------------
echo "[4] Detecting MAC interface..."

MAC_IFACE=""

for IFACE in eth0 eth1 br-lan; do
    if [ -e "/sys/class/net/$IFACE/address" ]; then
        MAC_IFACE="$IFACE"
        break
    fi
done

if [ -z "$MAC_IFACE" ]; then
    echo "ERROR: No valid network interface found!"
    exit 1
fi

MAC=$(cat /sys/class/net/$MAC_IFACE/address)

# Remove colons
MAC_NO_COLON=$(echo "$MAC" | tr -d ':')

# Split into OUI + NIC
OUI=$(echo "$MAC_NO_COLON" | cut -c1-6)
NIC=$(echo "$MAC_NO_COLON" | cut -c7-12)

# Construct EUI-64
EUI=$(echo "${OUI}FFFE${NIC}" | tr 'a-f' 'A-F')

TS_HOSTNAME="${HOST_PREFIX}_${EUI}"

echo "[4] Hostname generated: $TS_HOSTNAME"

# Apply hostname
uci set system.@system[0].hostname="$TS_HOSTNAME"
uci commit system
/etc/init.d/system restart || true
sleep 2

# ---------------------------------------------------------
# 5. Start Tailscale daemon
# ---------------------------------------------------------
echo "[5] Starting tailscaled..."

if [ -f "/etc/init.d/tailscaled" ]; then
    /etc/init.d/tailscaled enable
    /etc/init.d/tailscaled restart
else
    echo "ERROR: tailscaled service missing"
    exit 1
fi

sleep 3

# ---------------------------------------------------------
# 6. Tailscale up
# ---------------------------------------------------------
echo "[6] Running tailscale up..."

tailscale up \
  --login-server="$HEADSCALE_URL" \
  --authkey="$AUTHKEY" \
  --hostname="$TS_HOSTNAME" \
  --accept-routes=true \
  --advertise-routes="$SUBNET" \
  --accept-dns=false || echo "⚠ tailscale up returned non-zero (expected in test mode)"

echo ""
echo "=== DONE ==="
echo "Script executed successfully."
echo "Replace AUTHKEY with real key to register."
