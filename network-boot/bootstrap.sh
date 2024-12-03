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
apt install -y ansible git sshpass

# Ensure .ssh directory exists with correct permissions
mkdir -p "${REAL_HOME}/.ssh"
chmod 700 "${REAL_HOME}/.ssh"
chown ${REAL_USER}:${REAL_USER} "${REAL_HOME}/.ssh"

# Clone the repo
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

if ! sudo -E -u ${REAL_USER} git clone "$REPO_URL" "$REPO_DIR"; then
    echo "Failed to clone repository. Please check:"
    echo "1. The repository URL is correct"
    echo "2. You have access to the repository"
    echo "3. Your SSH key is properly added to GitHub (https://github.com/settings/keys)"
    echo "4. Test your GitHub SSH access: ssh -T git@github.com"
    exit 1
fi

# Set Ansible configuration file
export ANSIBLE_CONFIG="${REPO_DIR}/ansible.cfg"

# Setup Ansible temp directory
ANSIBLE_TMP="/tmp/.ansible-${REAL_USER}/tmp"
mkdir -p "${ANSIBLE_TMP}"
chown -R ${REAL_USER}:${REAL_USER} "/tmp/.ansible-${REAL_USER}"
chmod -R 700 "/tmp/.ansible-${REAL_USER}"

# Setup inventory
echo "Setting up Ansible inventory for local connection..."
INVENTORY_FILE="${REPO_DIR}/ansible/inventory/hosts"

# Copy the example inventory to hosts
if [ -f "${REPO_DIR}/ansible/inventory/example" ]; then
    sudo -u ${REAL_USER} cp "${REPO_DIR}/ansible/inventory/example" "${INVENTORY_FILE}"
    echo "Copied example inventory to hosts."
else
    echo "Error: Example inventory file does not exist at ${REPO_DIR}/ansible/inventory/example"
    exit 1
fi

# Get system IP or prompt for preferred IP
CURRENT_IP=$(hostname -I | awk '{print $1}')
read -p "Enter IP address to use [${CURRENT_IP}]: " PREFERRED_IP
PREFERRED_IP=${PREFERRED_IP:-$CURRENT_IP}

# Get hostname or prompt for preferred hostname
CURRENT_HOSTNAME=$(hostname)
read -p "Enter hostname to use [${CURRENT_HOSTNAME}]: " PREFERRED_HOSTNAME
PREFERRED_HOSTNAME=${PREFERRED_HOSTNAME:-$CURRENT_HOSTNAME}

# Modify the hosts inventory for local connection
sudo -u ${REAL_USER} sed -i "s/hostname/${PREFERRED_HOSTNAME}/" "${INVENTORY_FILE}"
sudo -u ${REAL_USER} sed -i "s/local_user/${REAL_USER}/" "${INVENTORY_FILE}"

# Verify the inventory file
echo "=== Inventory File Contents ==="
sudo -u ${REAL_USER} cat "${INVENTORY_FILE}"
echo "=== End Inventory File ==="

# Run the playbook with reduced verbosity
echo "Running Ansible playbook with local connection..."
cd "$REPO_DIR"
sudo -u ${REAL_USER} ansible-playbook -i ansible/inventory/hosts ansible/playbooks/setup-pi.yml -v