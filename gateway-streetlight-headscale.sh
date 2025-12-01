#!/bin/sh
# ---------------------------------------------------------
# RAK7289 WisGateOS2 - Headscale/Tailscale SD-card installer
# - Installs static Tailscale binary to /mnt/mmcblk0p1/tailscale
# - Creates /etc/init.d/tailscaled (WisGateOS2 compatible)
# - Generates hostname from EUI-64:  rak7289-<eui64>
# - Runs `tailscale up` if AUTHKEY is provided
#
# Usage (recommended):
#   AUTHKEY=tskey-auth-xxxxxxxxxxxxxxxxxxxxxxxxxxxx \
#     sh gateway-streetlight-headscale.sh
#
# Or edit AUTHKEY_DEFAULT below (less secure).
# ---------------------------------------------------------

set -e

### CONFIG ###
HEADSCALE_URL="https://hs.client.loranet.my"
SUBNET="192.168.230.0/24"
HOST_PREFIX="rak7289"

TS_MOUNT="/mnt/mmcblk0p1"
TS_DIR="$TS_MOUNT/tailscale"
TS_TGZ_URL="https://pkgs.tailscale.com/stable/tailscale_1.78.1_mipsle.tgz"
TS_TGZ="$TS_DIR/ts.tgz"

# Default auth key placeholder (will be overridden by ENV if set)
AUTHKEY_DEFAULT="b71f3ae0129e9f99870392c28967035c9059da4955dc4d82"
AUTHKEY="${AUTHKEY:-$AUTHKEY_DEFAULT}"

echo "=== RAK7289 WisGateOS2 Headscale/Tailscale SD-Card Installer ==="

# -------------------------------
# Basic environment checks
# -------------------------------
if ! command -v uci >/dev/null 2>&1; then
    echo "ERROR: This does not look like OpenWrt/WisGateOS2 (uci not found)."
    exit 1
fi

if [ ! -d "$TS_MOUNT" ]; then
    echo "ERROR: SD-card mount point $TS_MOUNT not found."
    echo "Make sure your SD card is mounted as $TS_MOUNT."
    exit 1
fi

echo "[1] WisGateOS2 detected ✔"
echo "[2] Using SD-card path: $TS_DIR"

mkdir -p "$TS_DIR"

# -------------------------------
# Download Tailscale static binary
# -------------------------------
echo "[3] Downloading Tailscale static archive..."
echo "    URL: $TS_TGZ_URL"

# Always refresh archive (you can change to 'if [ ! -f ... ]' if you want caching)
wget -O "$TS_TGZ" "$TS_TGZ_URL"

cd "$TS_DIR"
echo "[4] Extracting archive..."
tar -xzf "$TS_TGZ"

# Prefer 1.78.1 directory if present, else fall back to first tailscale_* dir
if [ -d "$TS_DIR/tailscale_1.78.1_mipsle" ]; then
    TS_EXTRACT_DIR="$TS_DIR/tailscale_1.78.1_mipsle"
else
    TS_EXTRACT_DIR="$(ls -d "$TS_DIR"/tailscale_* 2>/dev/null | head -n 1)"
fi

if [ ! -x "$TS_EXTRACT_DIR/tailscale" ] || [ ! -x "$TS_EXTRACT_DIR/tailscaled" ]; then
    echo "ERROR: tailscale/tailscaled binaries not found in $TS_EXTRACT_DIR"
    exit 1
fi

echo "[5] Using binaries from: $TS_EXTRACT_DIR"

# -------------------------------
# Install binaries via symlink
# -------------------------------
echo "[6] Installing tailscale binaries into /usr/bin ..."

ln -sf "$TS_EXTRACT_DIR/tailscale"  /usr/bin/tailscale
ln -sf "$TS_EXTRACT_DIR/tailscaled" /usr/bin/tailscaled

chmod +x /usr/bin/tailscale /usr/bin/tailscaled

# -------------------------------
# Prepare runtime directories
# -------------------------------
echo "[7] Preparing runtime directories..."
mkdir -p /var/run/tailscale
mkdir -p /var/lib/tailscale
[ -d /var/log ] || mkdir -p /var/log
[ -e /var/log/tailscaled.log ] || touch /var/log/tailscaled.log

# -------------------------------
# Create /etc/init.d/tailscaled
# -------------------------------
echo "[8] Creating /etc/init.d/tailscaled service..."

cat << 'EOF' > /etc/init.d/tailscaled
#!/bin/sh /etc/rc.common

START=99
STOP=10

start() {
    echo "Starting tailscaled..."
    mkdir -p /var/run/tailscale
    mkdir -p /var/lib/tailscale
    [ -e /var/log/tailscaled.log ] || touch /var/log/tailscaled.log

    /usr/bin/tailscaled \
        --state=/var/lib/tailscale/tailscaled.state \
        --socket=/var/run/tailscale/tailscaled.sock \
        >> /var/log/tailscaled.log 2>&1 &
}

stop() {
    echo "Stopping tailscaled..."
    killall tailscaled 2>/dev/null || true
}
EOF

chmod +x /etc/init.d/tailscaled
/etc/init.d/tailscaled enable

# -------------------------------
# Generate hostname from EUI-64
# -------------------------------
echo "[9] Generating hostname from EUI-64..."

MAC_IF=""
for IF in br-lan eth0 apcli0; do
    if [ -e "/sys/class/net/$IF/address" ]; then
        MAC_IF="$IF"
        break
    fi
done

if [ -z "$MAC_IF" ]; then
    echo "WARNING: Could not find interface for MAC (using default hostname)."
    TS_HOSTNAME="$HOST_PREFIX-unknown"
else
    MAC=$(cat "/sys/class/net/$MAC_IF/address")
    MAC_NO_COLON=$(echo "$MAC" | tr -d ':')

    OUI=${MAC_NO_COLON%??????}
    NIC=${MAC_NO_COLON#??????}
    # Build EUI-64 and force lowercase
    EUI=$(echo "${OUI}FFFE${NIC}" | tr 'A-F' 'a-f')

    TS_HOSTNAME="${HOST_PREFIX}-${EUI}"
fi

# Ensure hostname is DNS-safe + lowercase
TS_HOSTNAME=$(echo "$TS_HOSTNAME" | tr 'A-Z' 'a-z')

echo "    Selected hostname: $TS_HOSTNAME"

# Apply to system hostname (best-effort)
uci set system.@system[0].hostname="$TS_HOSTNAME" 2>/dev/null || true
uci commit system 2>/dev/null || true

# -------------------------------
# Start tailscaled
# -------------------------------
echo "[10] Starting tailscaled service..."
/etc/init.d/tailscaled stop >/dev/null 2>&1 || true
/etc/init.d/tailscaled start
sleep 2

# -------------------------------
# Run tailscale up (if AUTHKEY provided)
# -------------------------------
if echo "$AUTHKEY" | grep -q "TSKEY_AUTH_PLACEHOLDER"; then
    echo "⚠ AUTHKEY not provided."
    echo "   Skipping 'tailscale up'."
    echo ""
    echo "To register this gateway, run:"
    echo "  AUTHKEY=tskey-auth-xxxxxxxxxxxxxxxxxxxxxxxxxxxx \\"
    echo "    sh gateway-streetlight-headscale.sh"
else
    echo "[11] Running tailscale up against Headscale..."
    tailscale up \
        --login-server="$HEADSCALE_URL" \
        --authkey="$AUTHKEY" \
        --hostname="$TS_HOSTNAME" \
        --accept-routes=true \
        --advertise-routes="$SUBNET" \
        --accept-dns=false || true
fi

echo ""
echo "=== DONE ==="
echo "tailscaled installed to SD-card and service enabled."
echo "Hostname: $TS_HOSTNAME"
echo "You can check status with:  tailscale status"
