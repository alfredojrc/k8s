# Kubernetes Cluster Manager Documentation

## Overview

The `k8s-manager.sh` script provides a comprehensive solution for managing a Kubernetes cluster on VMware Fusion. This tool simplifies the deployment, configuration, and management of multi-node Kubernetes clusters in a local development environment.

## Table of Contents

1. [Getting Started](#getting-started)
2. [Main Features](#main-features)
3. [Detailed Documentation](#detailed-documentation)
4. [Prerequisites](#prerequisites)
5. [Usage](#usage)
6. [Configuration](#configuration)
7. [Troubleshooting](#troubleshooting)

## Getting Started

To start using the Kubernetes Cluster Manager:

1. Ensure all prerequisites are installed (see [Prerequisites](#prerequisites))
2. Run the script: `./k8s-manager.sh`
3. Navigate through the interactive menu to perform various operations

## Main Features

The Kubernetes Cluster Manager provides the following key features:

1. **Full Kubernetes Deployment**
   - Deploy a complete Kubernetes cluster with a single command
   - Includes HAProxy load balancers for high availability
   - Configures master and worker nodes automatically

2. **VM Management**
   - Create VMs with appropriate resources for Kubernetes components
   - Check VM status and network configuration
   - Power on/off VMs as needed
   - Update VM IP addresses

3. **Snapshot Management**
   - Create consistent snapshots across all VMs
   - Roll back to previous states when needed
   - Delete snapshots to reclaim disk space
   - Manage snapshots for individual VMs

4. **Terraform Integration**
   - Uses Terraform for infrastructure configuration
   - Provides integration with cloud-init for VM provisioning

5. **Networking**
   - Configures networking between VMs
   - Sets up load balancing for the Kubernetes API server

## Detailed Documentation

For more detailed documentation on specific features, refer to these guides:

- [Snapshot Management](snapshot_management.md) - Comprehensive guide to VM snapshot operations
- VM Deployment (Coming Soon) - Guide to creating and configuring VMs
- Kubernetes Deployment (Coming Soon) - Guide to deploying Kubernetes on the VMs
- Networking Configuration (Coming Soon) - Guide to configuring network settings

## Prerequisites

The Kubernetes Cluster Manager requires the following prerequisites:

1. **VMware Fusion** - For creating and managing virtual machines
2. **qemu-img** - For disk image manipulation
3. **mkisofs** - For creating cloud-init ISO images
4. **Terraform** - For infrastructure configuration
5. **SSH Key Pair** - For secure access to VMs

These prerequisites are automatically checked when running the script.

## Usage

The script provides an interactive menu interface. Run `./k8s-manager.sh` and select from the following options:

```
Kubernetes Cluster Management Menu
1) Deploy Kubernetes Cluster (Full Workflow)
2) Create all VMs and basic configuration
3) Check VM status and network configuration
4) Manage snapshots (submenu)
5) Delete all VMs
6) Deploy Kubernetes on existing VMs
7) Power on all VMs
8) Shutdown all VMs
9) Update VM IP addresses
0) Exit
```

## Configuration

The script uses the following key configuration settings:

- **Base Image Path**: `$HOME/godz/k8s/base_images/noble-server-cloudimg-arm64.img`
- **VM Cluster Directory**: `/Users/alf/VMs/k8s_cluster`
- **VM Disk Size**: 40GB (configurable)
- **SSH Public Key**: `$HOME/.ssh/id_ed25519.pub`

These settings can be modified in the script if needed.

## Troubleshooting

If you encounter issues:

1. Check that all prerequisites are installed correctly
2. Verify VMware Fusion is properly configured
3. Ensure the base image is accessible
4. Check VM disk space and resources
5. Examine the Terraform logs for deployment issues

For snapshot-specific troubleshooting, refer to the [Snapshot Management](snapshot_management.md) documentation. 