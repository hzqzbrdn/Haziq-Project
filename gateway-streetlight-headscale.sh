#!/bin/sh
# ---------------------------------------------------------
# RAK7289 WisGateOS 2 - Headscale/Tailscale Auto Setup
# STATIC MIPSLE VERSION (no opkg required)
# ---------------------------------------------------------

set -e

### CONFIG ###
HEADSCALE_URL="https://hs.client.loranet.my"
SUBNET="192.168.230.0/24"
HOST_PREFIX="RAK7289"

# User must pass AUTHKEY:
# Example:
# AUTHKEY=tskey-auth-xxxxxx sh script.sh
AUTHKEY="${AUTHKEY:key-auth-a1cafb62710fb075a66ed85f01e79796a28910432f5f160d}"

if [ "$AUTHKEY" = "key-auth-a1cafb62710fb075a66ed85f01e79796a28910432f5f160d" ]; then
    echo "⚠ WARNING: No AUTHKEY supplied."
    echo "Run script like:"
    echo "AUTHKEY=tskey-auth-xxxxx sh gateway.sh"
fi

echo "=== WisGateOS2 Headscale Setup (Static Binary) ==="

# -------------------------------
# Detect OpenWrt/WisGateOS
# -------------------------------
if ! command -v uci >/dev/null 2>&1; then
    echo "ERROR: Not an OpenWrt/WisGateOS system."
    exit 1
fi

echo "[1] WisGateOS2 detected ✔"

# -------------------------------
# Download Tailscale static binary
# -------------------------------
echo "[2] Downloading Tailscale static binary..."

TS_URL="https://pkgs.tailscale.com/stable/tailscale_1.78.1_mipsle.tgz"

wget -qO /tmp/ts.tgz "$TS_URL" || {
    echo "❌ Failed to download Tailscale."
    exit 1
}

cd /tmp
tar -xzf ts.tgz

# -------------------------------
# Install binaries
# -------------------------------
echo "[3] Installing Tailscale binaries..."

mv tailscale /usr/bin/
mv tailscaled /usr/sbin/

chmod +x /usr/bin/tailscale
chmod +x /usr/sbin/tailscaled

# -------------------------------
# Create service if not exists
# -------------------------------
echo "[4] Preparing tailscaled service..."

SERVICE_FILE="/etc/init.d/tailscaled"

if [ ! -e "$SERVICE_FILE" ]; then
cat <<'EOF' > "$SERVICE_FILE"
#!/bin/sh /etc/rc.common
START=99

start() {
    /usr/sbin/tailscaled --state=/var/lib/tailscale/tailscaled.state \
        --socket=/var/run/tailscale/tailscaled.sock &
}

stop() {
    killall tailscaled 2>/dev/null
}
EOF

chmod +x "$SERVICE_FILE"
fi

/etc/init.d/tailscaled enable
/etc/init.d/tailscaled restart

sleep 2

# -------------------------------
# Generate hostname from MAC → EUI64
# -------------------------------
echo "[5] Generating EUI hostname..."

for IF in eth0 eth1 br-lan; do
    if [ -e "/sys/class/net/$IF/address" ]; then
        MAC_IF="$IF"
        break
    fi
done

MAC=$(cat /sys/class/net/$MAC_IF/address)
MAC_NO_COLON=$(echo "$MAC" | tr -d ':')

# Build EUI64
OUI=${MAC_NO_COLON%??????}
NIC=${MAC_NO_COLON#??????}
EUI=$(echo "${OUI}FFFE${NIC}" | tr 'a-f' 'A-F')

TS_HOSTNAME="${HOST_PREFIX}_${EUI}"
echo "[*] Hostname: $TS_HOSTNAME"

uci set system.@system[0].hostname="$TS_HOSTNAME"
uci commit system

# -------------------------------
# tailscale up
# -------------------------------
echo "[6] Starting Tailscale..."

tailscale up \
  --login-server="$HEADSCALE_URL" \
  --authkey="$AUTHKEY" \
  --hostname="$TS_HOSTNAME" \
  --accept-routes=true \
  --advertise-routes="$SUBNET" \
  --accept-dns=false || true

echo ""
echo "=== Setup Complete ==="
echo "Check node in Headscale dashboard."
