# Raspberry Pi Utilities Collection _(pi-tools)_

[![GitHub License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![standard-readme compliant](https://img.shields.io/badge/readme%20style-standard-brightgreen.svg?style=flat-square)](https://github.com/RichardLitt/standard-readme)

A collection of tools and utilities for Raspberry Pi systems, focusing on automation, networking, and system management.

## Table of Contents

- [Background](#background)
- [Tools](#tools)
  - [Network Boot Server](#network-boot-server)
- [Maintainer](#maintainer)
- [Contributing](#contributing)
- [License](#license)

## Background

The pi-tools repository serves as a centralized collection of scripts, configurations, and utilities for Raspberry Pi systems. These tools aim to simplify common tasks, automate configuration, and extend the functionality of Raspberry Pi devices across various use cases.

Each tool is contained in its own subdirectory with dedicated documentation and implementation details.

## Tools

### Network Boot Server

A bootstrap script and configuration for setting up a Raspberry Pi as a network boot server, allowing other Raspberry Pi devices to boot over the network without requiring SD cards.

**Key features:**
- Automated setup via bootstrap script
- SSH key configuration for GitHub integration
- Ansible playbook for complete server configuration
- NFS and Docker service setup

[View Network Boot Server Documentation](network-boot/)

## Maintainer

[Sean Brar](https://github.com/seanbrar)

## Contributing

Contributions are welcome! If you have a useful Raspberry Pi utility that fits the collection, please:

1. Create a well-documented subdirectory with your tool
2. Include a README following the same format as existing tools
3. Submit a pull request with a clear description of your addition

For bugs or feature requests, please open an issue describing the problem or enhancement.

## License

[MIT](LICENSE) © Sean Brar