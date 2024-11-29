#!/bin/bash
set -euo pipefail

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo"
    exit 1
fi

# Get the actual user (even when running with sudo)
REAL_USER=$(logname || who am i | awk '{print $1}')
REAL_HOME=$(eval echo ~${REAL_USER})

# Install required packages
apt update
apt install -y ansible git

# Ensure .ssh directory exists with correct permissions
mkdir -p "${REAL_HOME}/.ssh"
chmod 700 "${REAL_HOME}/.ssh"
chown ${REAL_USER}:${REAL_USER} "${REAL_HOME}/.ssh"

# Generate SSH key if it doesn't exist
if [ ! -f "${REAL_HOME}/.ssh/id_ed25519" ]; then
    ssh-keygen -t ed25519 -C "${REAL_USER}@$(hostname)" -N "" -f "${REAL_HOME}/.ssh/id_ed25519"
    chmod 600 "${REAL_HOME}/.ssh/id_ed25519"
    chmod 644 "${REAL_HOME}/.ssh/id_ed25519.pub"
    chown ${REAL_USER}:${REAL_USER} "${REAL_HOME}/.ssh/id_ed25519"*
fi

# Display the public key and instructions
echo -e "\nAdd this public key to GitHub:"
cat "${REAL_HOME}/.ssh/id_ed25519.pub"
echo -e "\nGo to: https://github.com/settings/ssh/new"
echo -e "\nPress Enter after adding the key to GitHub..."
read -r

# Test SSH connection to GitHub (assuming known_hosts is already set up)
echo "Testing SSH connection to GitHub..."
if ! sudo -u ${REAL_USER} ssh -T git@github.com 2>&1 | grep -q "successfully authenticated\|Hi.*You've successfully authenticated"; then
    echo "Error: Unable to authenticate with GitHub"
    echo "Make sure you've:"
    echo "  1. Completed the prerequisite SSH setup"
    echo "  2. Added the SSH key to your GitHub account"
    exit 1
fi

# Get repo URL from user or environment variable
REPO_URL="${NETWORK_BOOT_REPO:-}"
if [ -z "$REPO_URL" ]; then
    read -p "Enter your GitHub repo URL (git@github.com:username/repo.git): " REPO_URL
fi

# Validate repo URL format
if ! echo "$REPO_URL" | grep -qE '^git@github\.com:.+/.+\.git$'; then
    echo "Error: Invalid repository URL format"
    exit 1
fi

# Clone the repo
REPO_DIR="/opt/network-boot/repo"
mkdir -p "$REPO_DIR"
git clone "$REPO_URL" "$REPO_DIR"
cd "$REPO_DIR"

# Setup inventory
echo "Setting up Ansible inventory..."
cp ansible/inventory/example ansible/inventory/hosts

# Get IP address
IP_ADDR=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -z "$IP_ADDR" ]; then
    read -p "Enter IP address for this Pi: " IP_ADDR
fi

# Update inventory file with actual values
sed -i "s/192.168.2.X/$IP_ADDR/" ansible/inventory/hosts
sed -i "s/network-boot-01.example/$(hostname)/" ansible/inventory/hosts

# Run the playbook
echo "Running Ansible playbook..."
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/setup-pi.yml