#!/bin/bash
set -euo pipefail

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo"
    exit 1
fi

# Ensure .ssh directory exists with correct permissions
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Generate SSH key if it doesn't exist
if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -N "" -f ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519
    chmod 644 ~/.ssh/id_ed25519.pub
fi

# Display the public key and instructions
echo -e "\nAdd this public key to GitHub:"
cat ~/.ssh/id_ed25519.pub
echo -e "\nGo to: https://github.com/settings/ssh/new"
echo -e "\nPress Enter after adding the key to GitHub..."
read -r

# Test SSH connection to GitHub
ssh-keyscan github.com >> ~/.ssh/known_hosts 2>/dev/null
if ! ssh -T git@github.com 2>&1 | grep -q "successfully authenticated\|Hi.*You've successfully authenticated"; then
    echo "Error: Unable to authenticate with GitHub"
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

# Run the playbook
ansible-playbook ansible/playbooks/setup-pi.yml
