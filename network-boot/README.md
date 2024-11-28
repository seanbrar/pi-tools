# Raspberry Pi Network Boot Server Bootstrap

This script helps set up a Raspberry Pi as a network boot server. It handles the initial configuration including SSH keys, network settings, and running the necessary Ansible playbook.

## Prerequisites

- A fresh Raspberry Pi installation
- Root/sudo access
- The following packages installed:
  - git
  - ansible
  - docker
  - nfs-kernel-server
  - ssh

## Usage

1. Download the bootstrap script:
```bash
curl -O https://raw.githubusercontent.com/seanbrar/pi-tools/main/network-boot/bootstrap.sh
chmod +x bootstrap.sh
```

2. Run the script with sudo:
```bash
sudo ./bootstrap.sh
```

3. Follow the prompts to:
   - Select environment type (development/production)
   - Enter network configuration (IP address, gateway, netmask)
   - Provide your GitHub repository URL
   - Add the generated SSH key to your GitHub account

The script will set up your Pi with the specified configuration and run the Ansible playbook to complete the setup.

## Note

Ensure you have at least 10GB of free disk space and that the required ports (2049, 67, 69, 111) are available before running the script.