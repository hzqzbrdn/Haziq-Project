#!/bin/sh
# ---------------------------------------------------------
# RAK7289 WisGateOS 2 - Headscale/Tailscale Auto Setup
# STATIC MIPSLE VERSION (EXTRACTS TO SD-CARD)
# ---------------------------------------------------------

set -e

### CONFIG ###
HEADSCALE_URL="https://hs.client.loranet.my"
SUBNET="192.168.230.0/24"
HOST_PREFIX="RAK7289"

# AUTHKEY must be passed externally:
# Example:
# AUTHKEY=tskey-auth-xxxxx sh script.sh
AUTHKEY="tskey-auth-a1cafb62710fb075a66ed85f01e79796a28910432f5f160d"

if [ "$AUTHKEY" = "tskey-auth-a1cafb62710fb075a66ed85f01e79796a28910432f5f160d" ]; then
    echo "⚠ WARNING: AUTHKEY not supplied."
    echo "Run like:"
    echo "AUTHKEY=tskey-auth-xxxxx sh gateway.sh"
fi

echo "=== WisGateOS2 Headscale Setup (SD‑Card Version) ==="

# -------------------------------
# Detect WisGateOS (OpenWrt)
# -------------------------------
if ! command -v uci >/dev/null 2>&1; then
    echo "ERROR: Not WisGateOS/OpenWrt."
    exit 1
fi

echo "[1] WisGateOS2 detected ✔"

# -------------------------------
# Ensure SD‑card mount exists
# -------------------------------
TS_DIR="/mnt/mmcblk0p1/tailscale"

mkdir -p "$TS_DIR"

if [ ! -d "$TS_DIR" ]; then
    echo "❌ ERROR: SD-card not mounted at /mnt/mmcblk0p1"
    exit 1
fi

echo "[2] Using SD‑card path: $TS_DIR"

# -------------------------------
# Download Tailscale static binary
# -------------------------------
echo "[3] Downloading Tailscale static binary (mipsle)..."

TS_URL="https://pkgs.tailscale.com/stable/tailscale_1.78.1_mipsle.tgz"

# Download directly to SD-card (no /tmp)
wget -qO "$TS_DIR/ts.tgz" "$TS_URL" || {
    echo "❌ Download failed."
    exit 1
}

# -------------------------------
# Extract on SD‑card
# -------------------------------
echo "[4] Extracting to SD‑card…"

cd "$TS_DIR"
tar -xzf ts.tgz
rm -f ts.tgz

# -------------------------------
# Install binaries via symlink
# -------------------------------
echo "[5] Installing binaries..."

ln -sf "$TS_DIR/tailscale" /usr/bin/tailscale
ln -sf "$TS_DIR/tailscaled" /usr/sbin/tailscaled

chmod +x "$TS_DIR/tailscale"
chmod +x "$TS_DIR/tailscaled"

# -------------------------------
# Create tailscaled service if missing
# -------------------------------
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
# Generate EUI64 hostname from MAC
# -------------------------------
echo "[6] Generating unique hostname (EUI64)..."

for IF in eth0 eth1 br-lan; do
    if [ -e "/sys/class/net/$IF/address" ]; then
        MAC_IF="$IF"
        break
    fi
done

MAC=$(cat /sys/class/net/$MAC_IF/address)
MAC_NO_COLON=$(echo "$MAC" | tr -d ':')

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
echo "[7] Starting Tailscale..."

tailscale up \
  --login-server="$HEADSCALE_URL" \
  --authkey="$AUTHKEY" \
  --hostname="$TS_HOSTNAME" \
  --accept-routes=true \
  --advertise-routes="$SUBNET" \
  --accept-dns=false || true

echo ""
echo "=== Setup Complete ==="
echo "Node should now appear in Headscale dashboard."
