#!/bin/sh
# ---------------------------------------------------------
# WisGateOS2 (RAK7289) - Tailscale 1.56.1 SD-card installer
# - Static mipsle build (tiny footprint)
# - Stores binaries on SD-card
# - Creates /etc/init.d/tailscaled (procd)
# - Enables auto-start on boot
# - Watchdog via cron (auto-restart)
# - Joins Headscale automatically
# ---------------------------------------------------------

set -e

### USER CONFIG ###
AUTHKEY="b71f3ae0129e9f99870392c28967035c9059da4955dc4d82"
HEADSCALE_URL="https://hs.client.loranet.my"
ADVERTISE_ROUTES="192.168.230.0/24"

### PATHS & VERSION ###
TS_VER="1.56.1"
ARCH="mipsle"
TS_TGZ="tailscale_${TS_VER}_${ARCH}.tgz"
TS_URL="https://pkgs.tailscale.com/stable/${TS_TGZ}"

SD_MOUNT="/mnt/mmcblk0p1"
TS_DIR="${SD_MOUNT}/tailscale"

echo "=== WisGateOS2 Headscale SD-card Installer (Tailscale ${TS_VER}) ==="

# ---------------------------------------------------------
# 1) Basic checks
# ---------------------------------------------------------
if ! command -v opkg >/dev/null 2>&1; then
    echo "ERROR: This does not look like OpenWrt/WisGateOS2 (opkg missing)."
    exit 1
fi

if [ ! -d "${SD_MOUNT}" ]; then
    echo "ERROR: SD card not mounted at ${SD_MOUNT}"
    exit 1
fi

mkdir -p "${TS_DIR}"
cd "${TS_DIR}"

echo "[1] WisGateOS2 detected, SD card OK: ${TS_DIR}"

# ---------------------------------------------------------
# 2) Download Tailscale 1.56.1 tiny build
# ---------------------------------------------------------
echo "[2] Downloading Tailscale static binary:"
echo "    ${TS_URL}"

rm -f "${TS_TGZ}"
wget -O "${TS_TGZ}" "${TS_URL}"

# ---------------------------------------------------------
# 3) Extract archive
# ---------------------------------------------------------
echo "[3] Extracting archive..."
tar -xzf "${TS_TGZ}"

BIN_ROOT="${TS_DIR}/tailscale_${TS_VER}_${ARCH}"

if [ ! -x "${BIN_ROOT}/tailscale" ] || [ ! -x "${BIN_ROOT}/tailscaled" ]; then
    echo "ERROR: tailscale binaries not found in ${BIN_ROOT}"
    exit 1
fi

echo "    Using binaries from: ${BIN_ROOT}"

# ---------------------------------------------------------
# 4) Install symlinks into /usr/bin
# ---------------------------------------------------------
echo "[4] Installing symlinks to /usr/bin..."

ln -sf "${BIN_ROOT}/tailscale"  /usr/bin/tailscale
ln -sf "${BIN_ROOT}/tailscaled" /usr/bin/tailscaled

chmod +x /usr/bin/tailscale /usr/bin/tailscaled

# ---------------------------------------------------------
# 5) Prepare runtime directories
# ---------------------------------------------------------
echo "[5] Preparing runtime directories..."

mkdir -p /var/lib/tailscale
mkdir -p /var/run/tailscale
mkdir -p /var/log
[ -e /var/log/tailscaled.log ] || touch /var/log/tailscaled.log

# ---------------------------------------------------------
# 6) Create /etc/init.d/tailscaled (procd service)
#    + RAM-friendly env (no log upload)
# ---------------------------------------------------------
echo "[6] Creating /etc/init.d/tailscaled service..."

cat << 'EOF' > /etc/init.d/tailscaled
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    mkdir -p /var/lib/tailscale
    mkdir -p /var/run/tailscale
    [ -e /var/log/tailscaled.log ] || touch /var/log/tailscaled.log

    procd_open_instance
    procd_set_param env TS_NO_LOGS=1 TS_LOG_TARGET=stderr
    procd_set_param command /usr/bin/tailscaled \
        --state=/var/lib/tailscale/tailscaled.state \
        --socket=/var/run/tailscale/tailscaled.sock
    procd_set_param respawn
    procd_close_instance
}

stop_service() {
    killall tailscaled 2>/dev/null || true
}
EOF

chmod +x /etc/init.d/tailscaled
/etc/init.d/tailscaled enable

# ---------------------------------------------------------
# 7) Generate hostname from MAC (DNS-safe, lowercase)
# ---------------------------------------------------------
echo "[7] Generating hostname from MAC..."

IFACE="br-lan"
if [ ! -e "/sys/class/net/${IFACE}/address" ]; then
    IFACE="eth0"
fi

if [ ! -e "/sys/class/net/${IFACE}/address" ]; then
    HOSTNAME_TS="rak7289-unknown"
else
    MAC=$(cat "/sys/class/net/${IFACE}/address" | tr -d ':')
    SUFFIX=$(echo "${MAC}" | tail -c 5 | tr 'A-Z' 'a-z')
    HOSTNAME_TS="rak7289-${SUFFIX}"
fi

echo "    Hostname will be: ${HOSTNAME_TS}"

uci set system.@system[0].hostname="${HOSTNAME_TS}" 2>/dev/null || true
uci commit system 2>/dev/null || true

# ---------------------------------------------------------
# 8) Start tailscaled via init.d
# ---------------------------------------------------------
echo "[8] Starting tailscaled service..."
/etc/init.d/tailscaled stop >/dev/null 2>&1 || true
/etc/init.d/tailscaled start
sleep 3

# ---------------------------------------------------------
# 9) Run 'tailscale up' to Headscale
# ---------------------------------------------------------
echo "[9] Running 'tailscale up' to Headscale..."

tailscale up \
    --login-server="${HEADSCALE_URL}" \
    --authkey="${AUTHKEY}" \
    --hostname="${HOSTNAME_TS}" \
    --accept-dns=false 

# ---------------------------------------------------------
# 10) Create lightweight watchdog script + cron
# ---------------------------------------------------------
echo "[10] Installing watchdog..."

cat << 'EOF' > /usr/bin/tailscale-watchdog.sh
#!/bin/sh
if ! pgrep tailscaled >/dev/null 2>&1; then
    /etc/init.d/tailscaled restart
fi
EOF

chmod +x /usr/bin/tailscale-watchdog.sh

# add to cron if not already there
if ! grep -q "tailscale-watchdog.sh" /etc/crontabs/root 2>/dev/null; then
    echo "*/1 * * * * /usr/bin/tailscale-watchdog.sh" >> /etc/crontabs/root
fi

/etc/init.d/cron restart 2>/dev/null || true

# ---------------------------------------------------------
# 11) Done
# ---------------------------------------------------------
echo ""
echo "=== DONE ==="
echo "tailscaled installed to SD-card, service enabled and watchdog active."
echo "Hostname: ${HOSTNAME_TS}"
echo "Check status with:  tailscale status"
