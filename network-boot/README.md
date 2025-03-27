# Raspberry Pi Network Boot Server Bootstrap

[![standard-readme compliant](https://img.shields.io/badge/readme%20style-standard-brightgreen.svg?style=flat-square)](https://github.com/RichardLitt/standard-readme)
[![Tested on Raspberry Pi 4](https://img.shields.io/badge/tested%20on-Raspberry%20Pi%204-red)](https://www.raspberrypi.com/)

A bootstrap script to configure a Raspberry Pi as a network boot server, handling SSH keys, network settings, and Ansible playbook execution.

## Table of Contents

- [Background](#background)
- [Prerequisites](#prerequisites)
- [Install](#install)
- [Usage](#usage)
- [Notes](#notes)

## Background

This tool automates the process of setting up a Raspberry Pi as a network boot server. Network booting allows other Raspberry Pi devices to operate without SD cards by loading their operating system from this server over the network.

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

## Install

Download the bootstrap script:
```bash
# Option 1: Latest version (might be cached)
curl -O https://raw.githubusercontent.com/seanbrar/pi-tools/main/network-boot/bootstrap.sh

# Option 2: Force latest version (recommended)
curl -O "https://raw.githubusercontent.com/seanbrar/pi-tools/main/network-boot/bootstrap.sh?$(date +%s)"
chmod +x bootstrap.sh
```

## Usage

Run the script:
```bash
# Option 1: Enter repo URL when prompted
sudo -E ./bootstrap.sh

# Option 2: Set repo URL via environment variable
export NETWORK_BOOT_REPO="git@github.com:username/repo.git"
sudo -E ./bootstrap.sh
```

Follow the prompts to:
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

## Notes

- Ensure you have at least 10GB of free disk space
- The script can be safely re-run if needed
- All configurations will be stored in `/opt/network-boot`