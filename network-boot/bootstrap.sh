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

# Package management
REQUIRED_PACKAGES=("git" "ansible" "nfs-kernel-server" "openssh-client")
MISSING_PACKAGES=()

echo "Checking for required packages..."
for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! dpkg-query -W -f='${Status}' $package 2>/dev/null | grep -q "install ok installed"; then
        MISSING_PACKAGES+=("$package")
    fi
done

if [ ${#MISSING_PACKAGES[@]} -ne 0 ]; then
    echo "The following required packages are missing:"
    printf '%s\n' "${MISSING_PACKAGES[@]}"
    
    read -r -p "Would you like to install them now? [y/N] " response
    if [[ "$response" =~ ^[Yy] ]]; then
        apt-get update
        apt-get install -y "${MISSING_PACKAGES[@]}"
    else
        echo "Cannot continue without required packages."
        exit 1
    fi
fi

# Check for required commands (simplified since we're checking packages)
REQUIRED_COMMANDS=("ssh-keygen" "ansible-playbook" "exportfs")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: Required command '$cmd' not found even after package installation"
        exit 1
    fi
done

# Check if ports are available
for port in "${REQUIRED_PORTS[@]}"; do
    echo "Checking port $port..."
    if [ "$port" = "2049" ] || [ "$port" = "111" ]; then
        if ! netstat -tuln | grep -q ":${port}.*LISTEN"; then
            echo "Error: NFS port $port is not listening as expected"
            exit 1
        fi
    else
        if netstat -tuln | grep ":${port} " | grep -qv "127.0.0.1"; then
            echo "Error: Port $port is already in use on external interfaces"
            exit 1
        fi
    fi
done

# IP Address Validation
validate_ip() {
    local ip=$1
    local stat=1

    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=($ip)
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?
    fi
    return $stat
}

echo "Enter IP address for this Pi: "
read ip_address
if ! validate_ip $ip_address; then
    echo "Invalid IP address format."
    exit 1
fi

echo "Enter network gateway: "
read gateway
if ! validate_ip $gateway; then
    echo "Invalid gateway format."
    exit 1
fi

echo "Enter netmask [255.255.255.0]: "
read netmask
netmask=${netmask:-"255.255.255.0"}  # Use default if empty
if ! validate_ip $netmask; then
    echo "Invalid netmask format."
    exit 1
fi

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
  ip: "${ip_address}"
  hostname: "${HOSTNAME}${HOSTNAME_SUFFIX}"
  netmask: "${netmask}"
  gateway: "${gateway}"
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
ip addr show | grep -q "$ip_address" || echo "Warning: Expected IP address not found"

echo "Bootstrap complete! Please verify your network configuration."
