#!/bin/bash
set -e

echo "==============================================="
echo "  Bivocom TG465 Headscale Installer By Haziq"
echo "==============================================="
echo "Detecting LAN subnet..."

LAN_IP=$(ip -4 addr show br-lan 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1)
if [ -z "$LAN_IP" ]; then
    LAN_IP=$(ip -4 addr show eth0 | grep inet | awk '{print $2}' | cut -d/ -f1)
fi

if [ -z "$LAN_IP" ]; then
    echo "❌ Cannot detect LAN IP! Aborting."
    exit 1
fi

SUBNET=$(echo "$LAN_IP" | cut -d '.' -f3)
LAN_ROUTE="192.168.$SUBNET.0/24"

echo "• LAN IP detected: $LAN_IP"
echo "• Host subnet: $SUBNET"
echo "• Route to advertise: $LAN_ROUTE"
echo ""

echo "Choose project type:"
echo "1) Flood Project"
echo "2) Traffic Light Project"
read -p "Select 1 or 2: " PROJECT

case $PROJECT in
    1)
        PREFIX="bivo-flood-"
        AUTHKEY="6bbfb37455f2d73c35fb4b3669f07374eef3e4efd68e5283"
        ;;
    2)
        PREFIX="bivo-tl-"
        AUTHKEY="148c989b9f9c1218ac271683afb22e44a9a963474c74bf49"
        ;;
    *)
        echo "❌ Invalid option"
        exit 1
        ;;
esac

HOSTNAME="${PREFIX}${SUBNET}"

echo "Hostname will be: $HOSTNAME"
echo "Auth key selected: (hidden)"
echo ""

echo "==============================================="
echo "   Installing Tailscale 1.78 (Ubuntu ARM64)"
echo "==============================================="

curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.list | \
  sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null

sudo apt update
sudo apt install -y tailscale

echo "==============================================="
echo "   Applying Hostname + Headscale Login"
echo "==============================================="

tailscale up \
  --login-server=https://hs.client.loranet.my \
  --authkey=${AUTHKEY} \
  --hostname=${HOSTNAME} \
  --advertise-routes=${LAN_ROUTE} \
  --accept-routes=true \
  --accept-dns=false

echo "==============================================="
echo "   Enabling Auto‑Start + Watchdog"
echo "==============================================="

sudo systemctl enable tailscaled
sudo systemctl restart tailscaled

# watchdog: auto-reconnect if tailscaled dies
cat <<EOF | sudo tee /etc/systemd/system/tailscale-watchdog.service >/dev/null
[Unit]
Description=Tailscale Watchdog
After=network-online.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do
  pgrep tailscaled >/dev/null || systemctl restart tailscaled;
  sleep 10;
done'
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable tailscale-watchdog
sudo systemctl start tailscale-watchdog

echo ""
echo "==============================================="
echo "      ✔ INSTALLATION COMPLETE"
echo "==============================================="
echo "Device registered as: $HOSTNAME"
echo "Advertised route: $LAN_ROUTE"
echo "Watchdog active, auto‑reconnect enabled"
echo "==============================================="
