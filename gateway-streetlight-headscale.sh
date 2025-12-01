#!/bin/sh
# ---------------------------------------------------------
# WisGateOS2 - Tailscale SD‑Card Installer + Auto‑Startup
# ---------------------------------------------------------

set -e

### USER CONFIG ###
AUTHKEY="b71f3ae0129e9f99870392c28967035c9059da4955dc4d82"
HEADSCALE_URL="https://hs.client.loranet.my"
ADVERTISE_ROUTES="192.168.230.0/24"
SD_PATH="/mnt/mmcblk0p1/tailscale"
TS_VERSION="1.56.1"
ARCH="mipsle"
TS_TGZ="tailscale_${TS_VERSION}_${ARCH}.tgz"

echo "=== WisGateOS2 Headscale Auto‑Installer (SD‑Card Version) ==="

# ---------------------------------------------------------
# 1) Verify SD card
# ---------------------------------------------------------
if [ ! -d /mnt/mmcblk0p1 ]; then
    echo "ERROR: SD card not detected at /mnt/mmcblk0p1"
    exit 1
fi
mkdir -p "$SD_PATH"

# ---------------------------------------------------------
# 2) Download static Tailscale
# ---------------------------------------------------------
echo "[1] Downloading Tailscale static binary..."
cd "$SD_PATH"
wget -q "https://pkgs.tailscale.com/stable/${TS_TGZ}"

echo "[2] Extracting..."
tar -xzf "${TS_TGZ}"

TS_DIR="${SD_PATH}/tailscale_${TS_VERSION}_${ARCH}"

# ---------------------------------------------------------
# 3) Install into /usr/bin using symlinks
# ---------------------------------------------------------
echo "[3] Installing symlinks..."
ln -sf "${TS_DIR}/tailscale" /usr/bin/tailscale
ln -sf "${TS_DIR}/tailscaled" /usr/bin/tailscaled
chmod +x /usr/bin/tailscale /usr/bin/tailscaled

# ---------------------------------------------------------
# 4) Create state + log directories
# ---------------------------------------------------------
mkdir -p /var/lib/tailscale
mkdir -p /var/log
touch /var/log/tailscaled.log

# ---------------------------------------------------------
# 5) Create init.d service
# ---------------------------------------------------------
echo "[4] Creating service /etc/init.d/tailscaled"

cat << 'EOF' > /etc/init.d/tailscaled
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
    mkdir -p /var/run/tailscale
    procd_open_instance
    procd_set_param command /usr/bin/tailscaled \
        --state=/var/lib/tailscale/tailscaled.state \
        --socket=/var/run/tailscale/tailscaled.sock \
        --verbose=1
    procd_set_param respawn
    procd_close_instance
}

stop_service() {
    killall tailscaled 2>/dev/null
}
EOF

chmod +x /etc/init.d/tailscaled
/etc/init.d/tailscaled enable

# ---------------------------------------------------------
# 6) Generate hostname from MAC
# ---------------------------------------------------------
MAC=$(cat /sys/class/net/eth0/address | tr -d ':')
HOST="RAK7289-$(echo $MAC | tail -c 5)"
echo "[5] Hostname: $HOST"

# ---------------------------------------------------------
# 7) Start Tailscale daemon
# ---------------------------------------------------------
echo "[6] Starting tailscaled..."
/etc/init.d/tailscaled restart
sleep 3

# ---------------------------------------------------------
# 8) Login to Headscale
# ---------------------------------------------------------
echo "[7] Running tailscale up..."
tailscale up \
  --login-server="${HEADSCALE_URL}" \
  --authkey="${AUTHKEY}" \
  --hostname="${HOST}" \
  --accept-routes=true \
  --advertise-routes="${ADVERTISE_ROUTES}" \
  --accept-dns=false

echo ""
echo "=== Installation Complete ==="
echo "Tailscale is now running and will auto‑start on reboot."
tailscale status
