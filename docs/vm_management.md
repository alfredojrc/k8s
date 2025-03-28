# VM Management Documentation

## Overview

The VM management functionality in k8s-manager.sh provides tools for creating, configuring, monitoring, and controlling the virtual machines that make up your Kubernetes cluster. This documentation covers how to use these features effectively.

## Table of Contents

1. [Creating VMs](#creating-vms)
2. [VM Configuration](#vm-configuration)
3. [Checking VM Status](#checking-vm-status)
4. [Power Management](#power-management)
5. [IP Address Management](#ip-address-management)
6. [Removing VMs](#removing-vms)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

## Creating VMs

The script provides options to create the complete set of VMs needed for a Kubernetes cluster.

### Creating All VMs

To create all the VMs for your Kubernetes cluster:

1. From the main menu, select option 2: "Create all VMs and basic configuration"
2. The script will:
   - Download the base image if needed
   - Create the following VMs:
     - HAProxy load balancers (haproxy1, haproxy2)
     - Kubernetes master nodes (k8s-master1, k8s-master2, k8s-master3)
     - Kubernetes worker nodes (k8s-worker1, k8s-worker2)
   - Configure each VM with cloud-init
   - Start each VM and wait for it to boot

### VM Creation Process

The VM creation process includes:

1. Base image check or download
2. Disk creation from the base image
3. Cloud-init configuration generation
4. VMX file creation
5. VM startup
6. Recording VM IP addresses

## VM Configuration

Each VM is configured with:

- **CPU & Memory**: 
  - HAProxy VMs: 2 CPUs, 2GB RAM
  - Master nodes: 4 CPUs, 4GB RAM
  - Worker nodes: 4 CPUs, 4GB RAM

- **Disk**: 40GB disk by default (configurable)

- **Network**: NAT networking with DHCP

- **Authentication**: 
  - SSH key-based authentication using your ~/.ssh/id_ed25519.pub key
  - Ubuntu user with sudo privileges
  - Random password (stored in ~/.k8s_password)

- **Software**:
  - Ubuntu 24.04 LTS (Noble) base OS
  - Pre-installed packages: qemu-guest-agent, net-tools, curl, wget, vim, htop, tmux, bash-completion

## Checking VM Status

To check the status of your VMs:

1. From the main menu, select option 3: "Check VM status and network configuration"
2. The script will display:
   - Which VMs are running or stopped
   - The IP address of each running VM
   - Network interface information from within each VM
   - A validation of the vm-ips.env file against running VMs

Example output:

```
Checking VM status and network configuration

VM cluster directory: /Users/alf/VMs/k8s_cluster

VM IP Addresses from vm-ips.env:
haproxy1_ip: "192.168.64.10"
haproxy2_ip: "192.168.64.11"
master1_ip: "192.168.64.20"
master2_ip: "192.168.64.21"
master3_ip: "192.168.64.22"
worker1_ip: "192.168.64.30"
worker2_ip: "192.168.64.31"

Checking VM status and network configuration:

VM: haproxy1
VM path: /Users/alf/VMs/k8s_cluster/haproxy1.vmwarevm
VMX file: /Users/alf/VMs/k8s_cluster/haproxy1.vmwarevm/haproxy1.vmx
Status: Running
IP address: 192.168.64.10
...
```

## Power Management

The script provides options to power on and shut down your VMs.

### Power On All VMs

To power on all VMs:

1. From the main menu, select option 7: "Power on all VMs"
2. The script will:
   - Check for VMs in the VM_CLUSTER_DIR
   - Start any VM that is not already running
   - Show progress for each VM

### Shutdown All VMs

To shut down all VMs:

1. From the main menu, select option 8: "Shutdown all VMs"
2. Confirm the shutdown when prompted
3. The script will:
   - Find all running VMs
   - Attempt a graceful shutdown of each VM
   - Offer to force power off any VM that doesn't shut down gracefully

## IP Address Management

The script provides an option to update VM IP addresses.

### Update VM IP Addresses

To update VM IP addresses:

1. From the main menu, select option 9: "Update VM IP addresses"
2. The script will:
   - Check each VM for its current IP address
   - Update the vm-ips.env file with the current IP addresses
   - Display the updated IP addresses

This is particularly useful after:
- Creating new VMs
- Restarting VMs
- Network changes
- Before deploying Kubernetes

## Removing VMs

To remove all VMs:

1. From the main menu, select option 5: "Delete all VMs"
2. The script will:
   - Stop any running VMs
   - Remove the VM directory
   - Clean up related files (vm-ips.env, generated directory, Terraform state)

## Best Practices

1. **VM Creation**:
   - Create all VMs at once for a consistent environment
   - Allow time for VMs to fully boot before using them
   - Verify VM connectivity before deployment

2. **Resource Allocation**:
   - Ensure your host has enough resources for all VMs
   - Adjust CPU, memory, and disk configuration if needed

3. **Network Configuration**:
   - Update VM IP addresses after any network changes
   - Verify network connectivity between VMs

4. **VM Management**:
   - Use graceful shutdown when possible
   - Take snapshots before making major changes

## Troubleshooting

### Common Issues and Solutions

1. **VM Creation Fails**
   - Check disk space on your host machine
   - Verify the base image is accessible
   - Check for permissions issues in the VM directory

2. **VM Won't Start**
   - Check VMware Fusion is running properly
   - Verify the VMX file exists and is valid
   - Check your host has enough resources

3. **VM Network Issues**
   - Update VM IP addresses to get current IPs
   - Check VMware Fusion networking settings
   - Verify the VM's network adapter is properly configured

4. **VM Performance Issues**
   - Check resource allocation (CPU, memory)
   - Look for disk space issues
   - Consider snapshots that may be impacting performance

### Debugging Tools

The script provides several tools for troubleshooting:

1. **Check VM Status**: Use option 3 to get detailed information about each VM
2. **Update VM IPs**: Use option 9 to refresh IP address information
3. **VM Directory**: Examine the VM files in /Users/alf/VMs/k8s_cluster
4. **Logs**: Check VMware Fusion logs for VM-specific issues 