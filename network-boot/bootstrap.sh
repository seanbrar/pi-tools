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

# Function to test GitHub SSH connection with enhanced logging
test_github_ssh() {
    sudo -H -u ${REAL_USER} ssh -i ${REAL_HOME}/.ssh/id_ed25519 -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | tee /tmp/ssh_test_output.log
    grep -q "successfully authenticated" /tmp/ssh_test_output.log
}

# Check for existing SSH keys
if [ ! -f "${REAL_HOME}/.ssh/id_ed25519" ] && [ ! -f "${REAL_HOME}/.ssh/id_rsa" ]; then
    echo "No SSH keys found. Generating new Ed25519 key..."
    
    # Generate key as the real user
    sudo -u ${REAL_USER} ssh-keygen -t ed25519 -C "${REAL_USER}@$(hostname)" -N "" -f "${REAL_HOME}/.ssh/id_ed25519"
    
    # Set correct permissions
    chmod 600 "${REAL_HOME}/.ssh/id_ed25519"
    chmod 644 "${REAL_HOME}/.ssh/id_ed25519.pub"
    chown ${REAL_USER}:${REAL_USER} "${REAL_HOME}/.ssh/id_ed25519"*
    
    # Display instructions
    echo -e "\n=== GitHub SSH Key Setup Required ==="
    echo -e "1. Copy this public key (select and copy the entire line below):\n"
    cat "${REAL_HOME}/.ssh/id_ed25519.pub"
    echo -e "\n2. Go to: https://github.com/settings/ssh/new"
    echo -e "3. Give it a memorable title (e.g., $(hostname))"
    echo -e "4. Paste the key into the 'Key' field"
    echo -e "5. Click 'Add SSH key'\n"
    
    while true; do
        read -p "Press Enter after adding the key to GitHub (or 'q' to quit)..." response
        
        if [ "$response" == "q" ]; then
            echo "Setup aborted."
            exit 1
        fi
        
        echo "Testing GitHub SSH connection..."
        if test_github_ssh; then
            echo "SSH connection successful!"
            break
        else
            echo "SSH connection failed. Please verify that you added the key correctly."
            echo "Would you like to:"
            echo "1. Show the public key again"
            echo "2. Retry the connection test"
            echo "3. Quit"
            read -p "Enter your choice (1-3): " choice
            
            case $choice in
                1) cat "${REAL_HOME}/.ssh/id_ed25519.pub";;
                2) continue;;
                3) echo "Setup aborted."; exit 1;;
                *) echo "Invalid choice. Retrying connection test...";;
            esac
        fi
    done
else
    echo "Existing SSH key found. Testing GitHub connection..."
    
    # Start SSH agent and add the key if necessary
    eval "$(ssh-agent -s)"
    ssh-add "${REAL_HOME}/.ssh/id_ed25519" || true
    
    if ! test_github_ssh; then
        echo "SSH connection to GitHub failed. Please ensure:"
        echo "1. Your SSH key is added to GitHub (https://github.com/settings/keys)"
        echo "2. The SSH agent is running (eval \$(ssh-agent -s))"
        echo "3. Your key is added to the agent (ssh-add)"
        # Optionally, display the SSH test output for debugging
        cat /tmp/ssh_test_output.log
        exit 1
    fi
    echo "SSH connection successful!"
fi

# Get the repository URL
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

# Prepare the clone directory
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