#!/bin/bash

echo "************************************************"
echo "           Script created by: haziq"   
echo "************************************************"

# Update system
echo "Updating system..."
sudo apt update -y
sudo apt upgrade -y

# Install necessary dependencies
echo "Installing build-essential and python3..."
sudo apt install -y build-essential python3

# Install NVM (Node Version Manager)
echo "Installing NVM..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash

# Source NVM for the current shell session to make it available
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm

# Verify if NVM is installed and available
command -v nvm >/dev/null 2>&1 || { echo >&2 "NVM installation failed"; exit 1; }

# Install Node.js using NVM (Node.js version 18)
echo "Installing Node.js version 18..."
nvm install 18
nvm use 18
nvm alias default 18

# Install Node-RED
echo "Installing Node-RED..."
npm install -g --unsafe-perm node-red

# Install necessary Node-RED nodes (e.g., node-red-node-serialport)
echo "Installing Node-RED nodes..."
cd /home/$USER/.node-red
npm install node-red-node-serialport@2.0.3

cd ..
# Create a systemd service for Node-RED
echo "Setting up Node-RED systemd service..."

cat <<EOL | sudo tee /etc/systemd/system/nodered.service
[Unit]
Description=Node-RED
Documentation=http://nodered.org
After=network.target

[Service]
ExecStart=/bin/bash -c 'source /home/$USER/.nvm/nvm.sh && nvm use 18 && node-red'
User=$USER
Group=$USER
WorkingDirectory=/home/$USER
Restart=on-failure
Environment=NODE_RED_OPTIONS=-v
Environment=PATH=/home/$USER/.nvm/versions/node/v18.20.8/bin:$PATH
Environment=HOME=/home/$USER
Environment=USER=$USER
StandardOutput=journal
StandardError=journal
SyslogIdentifier=node-red

[Install]
WantedBy=multi-user.target
EOL

echo "Set permissions and reload systemd"
sudo chown -R $USER:$USER /home/$USER/.nvm
sudo systemctl daemon-reload

# Enable Node-RED to start on boot
echo "Enabling Node-RED to start on boot..."
sudo systemctl enable nodered

# Start Node-RED service
echo "Starting Node-RED..."
sudo systemctl start nodered

# Check the status of Node-RED
echo "Checking Node-RED status..."
sudo systemctl status nodered

echo "--------------------NODE-RED INSTALLED!-------------------------------------"
echo "............................................................................."
echo "---------------------IMPORTING FLOW INTO NODE-RED--------------------------"

echo "---------------------------------------------------------"
echo "Select a project to install its Node-RED flow:"
echo "1) Flood Fighter Project"
echo "2) Speed Sign Sensor Project (SSS)"
echo "3) Custom flow URL"
echo "---------------------------------------------------------"

read -p "Enter your choice (1-3): " choice

FLOW_URL=""

case $choice in
    1)
        FLOW_URL="https://raw.githubusercontent.com/hzqzbrdn/Haziq-Project/main/flood_fighter.json"
        echo "Selected: Flood Fighter Project"
        ;;
    2)
        FLOW_URL="https://raw.githubusercontent.com/hzqzbrdn/Haziq-Project/main/flows_SSS.json"
        echo "Selected: Speed Sign Sensor Project (SSS)"
        ;;
    3)
        read -p "Enter custom flow URL: " FLOW_URL
        ;;
    *)
        echo "Invalid selection. Exiting."
        exit 1
        ;;
esac

echo "Downloading selected flow..."
curl -sSL "$FLOW_URL" -o /home/$USER/.node-red/flows.json

echo "Restarting Node-RED..."
sudo systemctl restart nodered

echo "--------------------FLOW INSTALLED SUCCESSFULLY--------------------"


echo "--------------------FLOW IMPORTED AND NODE-RED RESTARTED!------------------"
echo "............................................................................."

echo "-----------Check and Modify Permissions for /dev/ttyS0 and /dev/ttyS3----------------------"

cat <<EOL | sudo tee /etc/udev/rules.d/99-serial.rules
KERNEL=="ttyS0", MODE="0666"
KERNEL=="ttyS3", MODE="0666"
EOL

sudo udevadm control --reload-rules
sudo udevadm trigger

echo "------------------------ttyS0 & ttyS3 MODIFIED---------------------------------"

echo "---------------------REBOOTING----------------------------------------------"

sudo reboot

