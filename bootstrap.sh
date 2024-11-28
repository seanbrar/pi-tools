#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

# Get username and hostname
USER=$(whoami)
HOSTNAME=$(hostname)

# Configuration
BASE_DIR="/opt/network-boot"
REQUIRED_PORTS=(2049 67 69 111)  # NFS and TFTP ports
REQUIRED_SPACE_GB=10

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo"
    exit 1
fi

# Check available disk space
AVAILABLE_SPACE=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE_GB" ]; then
    echo "Error: Insufficient disk space. Need at least ${REQUIRED_SPACE_GB}GB, have ${AVAILABLE_SPACE}GB"
    exit 1
fi

# Check for required commands
REQUIRED_COMMANDS=("git" "ssh-keygen" "ansible-playbook" "docker" "exportfs")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' not found"
        exit 1
    fi
done

# Check if ports are available
for port in "${REQUIRED_PORTS[@]}"; do
    if netstat -tuln | grep -q ":$port "; then
        echo "Error: Port $port is already in use"
        exit 1
    fi
done

# Get IP configuration
read -r -p "Enter IP address for this Pi: " PI_IP
read -r -p "Enter network gateway: " GATEWAY
read -r -p "Enter netmask [255.255.255.0]: " NETMASK
NETMASK=${NETMASK:-255.255.255.0}

# Validate IP addresses
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    for octet in $(echo "$ip" | tr '.' ' '); do
        if [[ $octet -lt 0 || $octet -gt 255 ]]; then
            return 1
        fi
    done
    return 0
}

for ip in "$PI_IP" "$GATEWAY" "$NETMASK"; do
    if ! validate_ip "$ip"; then
        echo "Invalid IP address format: $ip"
        exit 1
    fi
done

# Prompt for repo URL with validation
while true; do
    echo "Enter your GitHub repo URL (git@github.com:username/repo.git):"
    read -r REPO_URL
    if [[ "$REPO_URL" =~ ^git@github\.com:.+/.+\.git$ ]]; then
        break
    else
        echo "Invalid GitHub SSH URL format. Please try again."
    fi
done

# Prompt for environment
echo "Select environment:"
echo "1) Development"
echo "2) Production"
read -r -p "Enter choice [1-2]: " env_choice

case $env_choice in
    1) ENV="dev"; HOSTNAME_SUFFIX="-dev";;
    2) ENV="prod"; HOSTNAME_SUFFIX="";;
    *) echo "Invalid choice"; exit 1;;
esac

# Create temporary vars file for Ansible
VARS_FILE=$(mktemp)
cat > "$VARS_FILE" << EOF
network:
  ip: "${PI_IP}"
  hostname: "${HOSTNAME}${HOSTNAME_SUFFIX}"
  netmask: "${NETMASK}"
  gateway: "${GATEWAY}"
EOF

# Ensure .ssh directory exists with correct permissions
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Generate SSH key if it doesn't exist
if [ ! -f ~/.ssh/id_ed25519 ]; then
    echo "Generating new SSH key..."
    ssh-keygen -t ed25519 -C "${USER}@${HOSTNAME}" -N "" -f ~/.ssh/id_ed25519
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
echo "Testing GitHub SSH connection..."
if ! ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "Error: Unable to authenticate with GitHub"
    rm -f "$VARS_FILE"
    exit 1
fi

# Create required directories
echo "Creating base directory structure..."
mkdir -p "$BASE_DIR"
mkdir -p "$BASE_DIR/tftp/data/nfs/debian"
mkdir -p "$BASE_DIR/tftp/data/nfs/pios"

# Clone or update the repo
REPO_DIR=$(basename "$REPO_URL" .git)
if [ -d "$REPO_DIR" ]; then
    echo "Repository directory already exists. Updating..."
    cd "$REPO_DIR"
    git pull
else
    echo "Cloning repository..."
    git clone "$REPO_URL"
    cd "$REPO_DIR"
fi

# Run the appropriate playbook
PLAYBOOK_PATH="ansible/playbooks/setup-pi.yml"
if [ -f "$PLAYBOOK_PATH" ]; then
    echo "Running Ansible playbook..."
    ansible-playbook "$PLAYBOOK_PATH" -e "@$VARS_FILE"
else
    echo "Error: Ansible playbook not found at: $PLAYBOOK_PATH"
    rm -f "$VARS_FILE"
    exit 1
fi

# Clean up
rm -f "$VARS_FILE"

# Verify setup
echo "Verifying setup..."
# Check if NFS is running
if ! systemctl is-active --quiet nfs-kernel-server; then
    echo "Warning: NFS server is not running"
fi

# Check if Docker is running
if ! systemctl is-active --quiet docker; then
    echo "Warning: Docker is not running"
fi

# Final network check
echo "Checking network configuration..."
ip addr show | grep -q "$PI_IP" || echo "Warning: Expected IP address not found"

echo "Bootstrap complete! Please verify your network configuration."
