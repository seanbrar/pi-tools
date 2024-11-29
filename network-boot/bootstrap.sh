#!/bin/bash
set -euo pipefail

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo -E"
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
    echo "Generating new SSH key..."
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

# Get repo URL from user or environment variable
REPO_URL="${NETWORK_BOOT_REPO:-}"
if [ -z "$REPO_URL" ]; then
    read -p "Enter your GitHub repo URL (git@github.com:username/repo.git): " REPO_URL
fi

# Validate repo URL format
if ! echo "$REPO_URL" | grep -qE '^git@github\.com:.+/.+\.git$'; then
    echo "Error: Invalid repository URL format"
    echo "Expected format: git@github.com:username/repo.git"
    exit 1
fi

# Clone the repo
REPO_DIR="/opt/network-boot/repo"
echo "Cloning repository to ${REPO_DIR}..."
if [ -d "$REPO_DIR" ]; then
    echo "Repository directory already exists. Backing up..."
    mv "$REPO_DIR" "${REPO_DIR}.bak.$(date +%s)"
fi

# Create and set permissions on directories
mkdir -p "/opt/network-boot"
chown ${REAL_USER}:${REAL_USER} "/opt/network-boot"
mkdir -p "$REPO_DIR"
chown ${REAL_USER}:${REAL_USER} "$REPO_DIR"

if ! sudo -E -u ${REAL_USER} git clone "$REPO_URL" "$REPO_DIR"; then
    echo "Failed to clone repository. Please check:"
    echo "1. The repository URL is correct"
    echo "2. You have access to the repository"
    echo "3. Your SSH key is properly added to GitHub (https://github.com/settings/keys)"
    echo "4. Test your GitHub SSH access: ssh -T git@github.com"
    exit 1
fi

# Change to repo directory for Ansible operations
cd "$REPO_DIR"

# Setup inventory
echo "Setting up Ansible inventory..."
cp ansible/inventory/example ansible/inventory/hosts

# Get IP address
IP_ADDR=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -z "$IP_ADDR" ]; then
    read -p "Enter IP address for this Pi: " IP_ADDR
fi

# Get current username for Ansible
ANSIBLE_USER="${REAL_USER}"

# Update inventory file with actual values
sed -i "s/192.168.2.X/$IP_ADDR/" ansible/inventory/hosts
sed -i "s/network-boot-01.example/$(hostname)/" ansible/inventory/hosts
sed -i "s/your_username/$ANSIBLE_USER/" ansible/inventory/hosts

# Run the playbook
echo "Running Ansible playbook..."
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/setup-pi.yml