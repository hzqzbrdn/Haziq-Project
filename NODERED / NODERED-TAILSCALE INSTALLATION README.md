# **Node-RED / Tailscale Automated Installation Script**

This repository provides an automated Node-RED installation script for Linux-based systems. This script updates your system, installs dependencies, sets up Node-RED, and ensures it runs on boot using systemd.

## Introduction

This tutorial will guide you through using an automated script to install Node-RED on a Linux system. The script will set up:

**Node.js version 18**


## Node-RED and related packages


A systemd service to ensure Node-RED runs on boot

## Prerequisites

Before running the script, ensure the following:

A Linux-based system (e.g., Ubuntu, Debian, etc.)

A non-root user with sudo access

Internet access to download necessary packages

# How to Use the Script

You can run the script directly from GitHub without needing to download or save the file. Follow the instructions below:

## Option 1: Run the Script Directly from GitHub

To execute the script directly from GitHub, run the following command in your terminal:

1. Install Curl

`sudo apt install curl`

2. Install Bash

`sudo apt install bash`

3. **Copy**

`curl -sSL https://raw.githubusercontent.com/hzqzbrdn/node-red-installation/main/node-tailscale_install.sh | bash`


**This command will:**

Download the script

Automatically execute the installation process


## Option 2: Clone the Repository and Run the Script
Alternatively, you can clone the repository and run the script manually:

Clone the repository:

Copy

`git clone https://github.com/hzqzbrdn/node-red-installation.git
cd node-red-installation`

Make the script executable:

Copy

`chmod +x node-tailscale_install.sh`

Run the script:

Copy

`./node-tailscale_install.sh`

Verifying the Installation
After running the script, you can verify the Node-RED setup by:

**Checking the status of the Node-RED service:**

Copy

`sudo systemctl status nodered`


## Troubleshooting

Here are some common troubleshooting steps:

**Service fails to start:**

If Node-RED fails to start after reboot, check the service logs with:
Copy

`sudo journalctl -u nodered`

**Permission issues:**

Ensure the correct user has permission to access the required directories:
Copy

`sudo chown -R $USER:$USER /home/$USER/.nvm`

**Missing dependencies:**

If the script fails due to missing dependencies, ensure you have all necessary build tools:
Copy

`sudo apt install build-essential python3`


# **Contributing**

Feel free to fork this repository, submit issues, or contribute improvements. If you encounter any bugs or have feature requests, please open an issue on GitHub!
