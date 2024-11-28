# Raspberry Pi Network Boot Server Bootstrap

This script helps set up a Raspberry Pi as a network boot server. It handles the initial configuration including SSH keys, network settings, and running the necessary Ansible playbook.

## Prerequisites

- A fresh Raspberry Pi installation
- Root/sudo access
- The following packages installed:
  - git
  - ansible
  - nfs-kernel-server
  - ssh

## Usage

1. Download the bootstrap script:
```bash
# Option 1: Latest version (might be cached)
curl -O https://raw.githubusercontent.com/seanbrar/pi-tools/main/network-boot/bootstrap.sh

# Option 2: Force latest version (recommended)
curl -O "https://raw.githubusercontent.com/seanbrar/pi-tools/main/network-boot/bootstrap.sh?$(date +%s)"
```

2. Run the script with sudo:
```bash
# Option 1: Enter repo URL when prompted
sudo ./bootstrap.sh

# Option 2: Set repo URL via environment variable
export NETWORK_BOOT_REPO="git@github.com:username/repo.git"
sudo -E ./bootstrap.sh
```

3. Follow the prompts to:
   - Add the generated SSH key to your GitHub account
   - Enter your GitHub repository URL (if not set via environment variable)
   - Enter network configuration (IP address, gateway, netmask)

The script will:
1. Set up SSH authentication with GitHub
2. Clone your private repository
3. Run the Ansible playbook to complete the setup

## Note

Ensure you have at least 10GB of free disk space and that the required ports (2049, 67, 69, 111) are available before running the script.