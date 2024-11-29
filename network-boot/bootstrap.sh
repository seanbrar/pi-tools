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

# Setup SSH key for local Ansible operations
SSH_KEY_FILE="${REAL_HOME}/.ssh/ansible_local"
if [ ! -f "${SSH_KEY_FILE}" ]; then
    echo "Generating SSH key for Ansible..."
    sudo -u ${REAL_USER} ssh-keygen -t ed25519 -f "${SSH_KEY_FILE}" -N "" -C "ansible-local-${HOSTNAME}"
    
    # Clear existing ansible key entries from authorized_keys
    if [ -f "${REAL_HOME}/.ssh/authorized_keys" ]; then
        sudo -u ${REAL_USER} sed -i '/ansible-local-/d' "${REAL_HOME}/.ssh/authorized_keys"
    fi
    
    # Add new key
    sudo -u ${REAL_USER} cat "${SSH_KEY_FILE}.pub" >> "${REAL_HOME}/.ssh/authorized_keys"
    chmod 600 "${REAL_HOME}/.ssh/authorized_keys"
    chmod 600 "${SSH_KEY_FILE}"
    chmod 644 "${SSH_KEY_FILE}.pub"
fi

# Ensure SSH agent is using the correct key
eval $(ssh-agent -k 2>/dev/null || true)
eval $(ssh-agent)
ssh-add "${SSH_KEY_FILE}"

# Test SSH connection with verbose output
echo "Testing SSH connection..."
if ! ssh -i "${SSH_KEY_FILE}" -o StrictHostKeyChecking=no ${REAL_USER}@localhost echo "SSH key authentication successful"; then
    echo "SSH key authentication failed. Please check the SSH configuration."
    exit 1
fi

# Configure passwordless sudo for the user
SUDOERS_FILE="/etc/sudoers.d/ansible-user"
if [ ! -f "${SUDOERS_FILE}" ]; then
    echo "Configuring passwordless sudo..."
    echo "${REAL_USER} ALL=(ALL) NOPASSWD: ALL" > "${SUDOERS_FILE}"
    chmod 440 "${SUDOERS_FILE}"
fi

# Setup inventory
echo "Setting up Ansible inventory..."
cp "${REPO_DIR}/ansible/inventory/example" "${REPO_DIR}/ansible/inventory/hosts"

# Get IP address
IP_ADDR=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
if [ -z "$IP_ADDR" ]; then
    read -p "Enter IP address for this Pi: " IP_ADDR
fi

# Get current username for Ansible
ANSIBLE_USER="${REAL_USER}"

# Update inventory file with actual values
sed -i "s/192.168.2.X/$IP_ADDR/" "${REPO_DIR}/ansible/inventory/hosts"
sed -i "s/network-boot-01.example/$(hostname)/" "${REPO_DIR}/ansible/inventory/hosts"
sed -i "s/your_username/$ANSIBLE_USER/" "${REPO_DIR}/ansible/inventory/hosts"
sed -i "s|~/.ssh/ansible_local|${SSH_KEY_FILE}|" "${REPO_DIR}/ansible/inventory/hosts"

# Setup Ansible temp directory
ANSIBLE_TMP="/tmp/.ansible-${REAL_USER}"
mkdir -p "${ANSIBLE_TMP}/tmp"
chown -R ${REAL_USER}:${REAL_USER} "${ANSIBLE_TMP}"
chmod -R 700 "${ANSIBLE_TMP}"

# Set Ansible temp directory environment variables
export ANSIBLE_REMOTE_TMP="/tmp/.ansible-${REAL_USER}/tmp"
export ANSIBLE_LOCAL_TMP="/tmp/.ansible-${REAL_USER}/tmp"

# Debug SSH setup
echo "=== Debug SSH Setup ==="
echo "Contents of authorized_keys:"
cat "${REAL_HOME}/.ssh/authorized_keys"
echo ""
echo "SSH key permissions:"
ls -la "${REAL_HOME}/.ssh/ansible_local"*
echo ""
echo "Testing direct SSH with key:"
ssh -v -i "${SSH_KEY_FILE}" ${REAL_USER}@${IP_ADDR} echo "Test connection"
echo ""
echo "=== Inventory File Contents ==="
cat "${REPO_DIR}/ansible/inventory/hosts"
echo "=== End Debug ==="

# Test connection to actual IP before running Ansible
echo "Testing connection to ${IP_ADDR}..."
if ! ssh -i "${SSH_KEY_FILE}" -o StrictHostKeyChecking=no ${REAL_USER}@${IP_ADDR} echo "SSH key authentication successful"; then
    echo "SSH key authentication to ${IP_ADDR} failed. Please check:"
    echo "1. The IP address is correct"
    echo "2. SSH service is running"
    echo "3. SSH key authentication is properly configured"
    exit 1
fi

# Run the playbook
echo "Running Ansible playbook..."
cd "$REPO_DIR"
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/setup-pi.yml