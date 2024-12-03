# Raspberry Pi Network Boot Server Bootstrap

This script helps set up a Raspberry Pi as a network boot server. It handles the initial configuration including SSH keys, network settings, and running the necessary Ansible playbook.

## Prerequisites

- A fresh Raspberry Pi installation
- Root/sudo access
- The following packages installed:
  - git
  - ansible
- GitHub SSH setup:
  ```bash
  # Verify GitHub's host key (one-time step)
  ssh -T git@github.com
  # Type 'yes' when prompted
  # You'll see "Permission denied (publickey)" - this is expected
  ```

Note: Additional packages (nfs-kernel-server, docker.io, etc.) will be installed automatically by the Ansible playbook.

## Usage

1. Download the bootstrap script:
```bash
# Option 1: Latest version (might be cached)
curl -O https://raw.githubusercontent.com/seanbrar/pi-tools/main/network-boot/bootstrap.sh

# Option 2: Force latest version (recommended)
curl -O "https://raw.githubusercontent.com/seanbrar/pi-tools/main/network-boot/bootstrap.sh?$(date +%s)"
chmod +x bootstrap.sh
```

2. Run the script:
```bash
# Option 1: Enter repo URL when prompted
sudo -E ./bootstrap.sh

# Option 2: Set repo URL via environment variable
export NETWORK_BOOT_REPO="git@github.com:username/repo.git"
sudo -E ./bootstrap.sh
```

3. Follow the prompts to:
   - Add the generated SSH key to your GitHub account
   - Enter your GitHub repository URL (if not set via environment variable)
   - Confirm or modify the system IP address
   - Confirm or modify the system hostname

The script will:
1. Set up SSH authentication with GitHub
2. Clone your private repository to `/opt/network-boot/repo`
3. Run the Ansible playbook to:
   - Install required packages
   - Configure network settings
   - Set up NFS and Docker services
   - Configure the network boot environment

## Note

- Ensure you have at least 10GB of free disk space
- The script can be safely re-run if needed
- All configurations will be stored in `/opt/network-boot`