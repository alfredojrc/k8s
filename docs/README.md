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
7. [Snapshot Management](#snapshot-management)
8. [Troubleshooting](#troubleshooting)

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
   - Visual snapshot table showing status across all VMs

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

## Snapshot Management

The K8s Manager offers comprehensive management of VMware Fusion snapshots for your Kubernetes cluster VMs. For detailed documentation on snapshot management, see [Snapshot Management Documentation](snapshot_management.md).

Key features include:
- Create snapshots for all VMs simultaneously
- List snapshots in an easy-to-read table format
- Roll back VMs to previous snapshots
- Delete snapshots individually or across all VMs
- User-friendly console interface with color-coded status indicators

### Snapshot Menu

Access the snapshot management features by selecting option 4 from the main menu. This opens the Snapshot Management Submenu:

```
Snapshot Management Submenu
1) Create snapshot for all VMs
2) List snapshots for all VMs
3) Rollback to a specific snapshot
4) Delete a snapshot from all VMs
5) Delete a specific snapshot from a specific VM
6) Show manual snapshot deletion instructions
0) Return to main menu
```

### Creating Snapshots

Option 1 in the snapshot submenu allows you to create a snapshot for all VMs simultaneously. This ensures a consistent state across your entire Kubernetes cluster.

- You will be prompted to enter a name for the snapshot
- The script will create the snapshot in parallel across all VMs
- Each snapshot captures the complete VM state (memory, settings, and disk)

### Listing Snapshots

Option 2 displays a comprehensive table showing all VMs and their snapshots:

```
=== VM Snapshot Table ===
+-----------------+-------------+
| VM Name         | Snapshot   |
+-----------------+-------------+
| haproxy1        | ✓          |
| haproxy2        | ✖          |
| k8s-master1     | ✖          |
| k8s-master2     | ✖          |
| k8s-master3     | ✖          |
| k8s-worker1     | ✖          |
| k8s-worker2     | ✖          |
+-----------------+-------------+
```

The table has the following features:
- Color-coded VM names (green for running VMs, blue for powered-off VMs)
- Snapshot status indicators (✓ for existing snapshots, ✖ for absent snapshots)
- A summary showing the total number of VMs and snapshots
- A legend explaining the color coding and symbols

### Rolling Back to Snapshots

Option 3 allows you to restore a VM to a previous snapshot state:

1. Select the VM you want to roll back
2. Choose from the available snapshots for that VM
3. Confirm the rollback operation

The rollback process:
- Powers off the VM if it's running
- Reverts to the selected snapshot state
- Restarts the VM if it was running before

### Deleting Snapshots

Two options are available for deleting snapshots:

- Option 4: Delete a specific snapshot across all VMs that have it
  - Lists all unique snapshots across all VMs
  - Deletes the selected snapshot from every VM that has it
  - Performs the deletion in parallel for faster processing

- Option 5: Delete a specific snapshot from a specific VM
  - Select a VM first, then choose which snapshot to delete
  - Provides the option to power off the VM first if needed
  - Displays detailed status messages during the deletion process

### VMware Fusion Integration

The snapshot management utilizes VMware Fusion's `vmrun` command-line interface to:
- Create snapshots: `vmrun snapshot <vmx_file> <snapshot_name>`
- List snapshots: `vmrun listSnapshots <vmx_file>`
- Revert to snapshots: `vmrun revertToSnapshot <vmx_file> <snapshot_name>`
- Delete snapshots: `vmrun deleteSnapshot <vmx_file> <snapshot_name>`

The script also provides instructions for using VMware Fusion's UI to manage snapshots (accessible via option 6).

## Troubleshooting

If you encounter issues:

1. Check that all prerequisites are installed correctly
2. Verify VMware Fusion is properly configured
3. Ensure the base image is accessible
4. Check VM disk space and resources
5. Examine the Terraform logs for deployment issues

### Snapshot Troubleshooting

For snapshot-related issues:

- **Snapshot creation fails**: Ensure the VM has enough disk space and the VMware Fusion process has write permissions to the VM directory
- **Cannot delete snapshots**: Some snapshots can only be deleted when the VM is powered off, try shutting down the VM first
- **Rollback fails**: Check if the snapshot still exists and that there are no locks on the VM files
- **Snapshot table doesn't display**: This is usually a temporary issue; try running the list command again
- **Long snapshot names**: The table will automatically truncate very long snapshot names with '...' for better display

If problems persist, you can use VMware Fusion's UI directly to manage snapshots by following the VMware Fusion Tip provided in the snapshot display.

## Documentation Files

- [Main README](README.md) - This file, provides an overview of all functionality
- [Installation Guide](installation.md) - Detailed steps for installing dependencies
- [Snapshot Management](snapshot_management.md) - Detailed documentation for VM snapshot features
- [Network Configuration](network_config.md) - Guide for configuring networking 