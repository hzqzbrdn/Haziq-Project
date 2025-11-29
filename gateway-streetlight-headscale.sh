#!/bin/sh
# ---------------------------------------------------------
# RAK7289 WisGateOS 2 - Headscale / Tailscale auto setup
# TEST VERSION (contains placeholder AUTHKEY)
# ---------------------------------------------------------

set -e

### CONFIG ###
HEADSCALE_URL="https://hs.client.loranet.my"
SUBNET="192.168.230.0/24"
HOST_PREFIX="rak7289"
#####################################

# -------------------------------
# TEMP AUTHKEY FOR TESTING ONLY
# -------------------------------
AUTHKEY="${AUTHKEY:-a1cafb62710fb075a66ed85f01e79796a28910432f5f160d}"

if [ "$AUTHKEY" = "a1cafb62710fb075a66ed85f01e79796a28910432f5f160d" ]; then
    echo "⚠ WARNING: Using TEST AUTHKEY placeholder."
    echo "⚠ This will NOT register to Headscale."
    echo "✔ Script logic will still run for testing."
fi

echo "=== RAK7289 WisGateOS 2 Headscale Setup (Test Mode) ==="

# -------------------------------
# Detect OpenWrt/WisGateOS
# -------------------------------
if ! command -v opkg >/dev/null 2>&1; then
    echo "ERROR: This system is not OpenWrt/WisGateOS."
    exit 1
fi
echo "[*] WisGateOS2 detected."

# -------------------------------
# Install Tailscale if needed
# -------------------------------
if ! command -v tailscale >/dev/null 2>&1; then
    echo "[*] Installing Tailscale..."
    opkg update
    opkg install tailscale tailscaled || true
else
    echo "[*] Tailscale already installed."
fi

# -------------------------------
# Enable IPv4 forwarding
# -------------------------------
echo "[*] Enabling IPv4 forwarding..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null

# -------------------------------
# Detect MAC → EUI64
# -------------------------------
echo "[*] Detecting MAC interface..."

for IF in eth0 eth1 br-lan; do
    if [ -e "/sys/class/net/$IF/address" ]; then
        MAC_IFACE="$IF"
        break
    fi
done

MAC=$(cat /sys/class/net/$MAC_IFACE/address)
MAC_NO_COLON=$(echo "$MAC" | tr -d ':')
OUI=${MAC_NO_COLON%??????}
NIC=${MAC_NO_COLON#??????}
EUI=$(echo "${OUI}FFFE${NIC}" | tr 'a-f' 'A-F')

TS_HOSTNAME="${HOST_PREFIX}-${EUI}"

echo "[*] Generated hostname: $TS_HOSTNAME"

uci set system.@system[0].hostname="$TS_HOSTNAME"
uci commit system
/etc/init.d/system restart || true

# -------------------------------
# Start Tailscale daemon
# -------------------------------
echo "[*] Starting Tailscale service..."
/etc/init.d/tailscaled enable
/etc/init.d/tailscaled restart
sleep 2

# -------------------------------
# tailscale up command (test run)
# -------------------------------
echo "[*] Running tailscale up (test)..."

tailscale up \
  --login-server="$HEADSCALE_URL" \
  --authkey="$AUTHKEY" \
  --hostname="$TS_HOSTNAME" \
  --accept-routes=true \
  --advertise-routes="$SUBNET" \
  --accept-dns=false || true

echo ""
echo "=== TEST COMPLETE ==="
echo "Script executed successfully."
echo "Replace AUTHKEY with real key for full registration."
