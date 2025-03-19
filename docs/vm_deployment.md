# Kubernetes Cluster VM Deployment Documentation

## Overview

This document provides information about the VM deployment process for the Kubernetes cluster. It highlights critical sections in the scripts that should not be modified to ensure successful VM deployment.

## [LOCKED DOCUMENTATION: Do not modify the instructions in this section]

## Critical Components

### 1. Base Image Configuration

The base image is an Ubuntu 24.04 ARM64 cloud image that is used as the foundation for all VMs. This image must be properly converted and resized for use with VMware Fusion on Apple Silicon.

```bash
# Correct sequence for image conversion:
qemu-img convert -f raw -O qcow2 noble-server-cloudimg-arm64.img temp_disk.qcow2
qemu-img resize temp_disk.qcow2 40G
qemu-img convert -f qcow2 -O vmdk temp_disk.qcow2 noble-server-arm64.vmdk
```

**WARNING**: Do not skip the intermediate qcow2 step, as it ensures proper image conversion and resizing.

### 2. VMX File Configuration

The VMX file must be configured correctly for ARM64 VMs on Apple Silicon. The following settings are critical:

- `guestOS = "arm-ubuntu-64"` - Must specify ARM Ubuntu
- `virtualHW.version = "21"` - Required for Apple Silicon compatibility
- `nvme0.present = "TRUE"` - Use NVMe controller for disk
- `ethernet0.virtualDev = "e1000e"` - Required network adapter type
- `firmware = "efi"` - Must use EFI firmware

**WARNING**: Using incorrect settings will result in VMs that fail to boot or have performance issues.

### 3. Disk Creation Process

The disk creation process has been carefully designed to ensure compatibility with VMware Fusion on Apple Silicon:

1. Convert the raw cloud image to qcow2 format
2. Resize the qcow2 image to the desired size
3. Convert the qcow2 image to vmdk format for VMware

**WARNING**: Modifying this process may result in corrupted disk images or VMs that fail to boot.

### 4. Kubernetes Package Repositories

As of March 2024, the Kubernetes package repositories have changed. The legacy Google-hosted repositories (`apt.kubernetes.io` and `yum.kubernetes.io`) have been completely removed. The new community-owned repositories at `pkgs.k8s.io` have a different structure, with a dedicated repository for each Kubernetes minor version.

**WARNING**: For detailed information about the package repository changes and recommended installation methods, see [Package Repository Documentation](package_repository.md).

## VM Deployment Process

The VM deployment process consists of the following steps:

1. Check prerequisites
2. Remove existing VMs if needed
3. Download the base image if needed
4. Create VMs using the correct settings
5. Set up Terraform for cluster configuration
6. Deploy Kubernetes

Each step is handled by specific scripts:

- `create-ubuntu-vm.sh` - Creates individual VMs
- `create-vms.sh` - Orchestrates the creation of all VMs
- `deploy-k8s-cluster.sh` - Handles the entire deployment process

## Troubleshooting

If VM deployment fails, check for these common issues:

1. **VM doesn't boot**: Verify the VMX file has the correct settings, especially `guestOS`, `firmware`, and `nvme0` configuration.
2. **Disk image issues**: Ensure the disk creation process follows all three steps (raw → qcow2 → vmdk).
3. **Network connectivity issues**: Check that the ethernet adapter is set to `e1000e`.
4. **Kubernetes package repository errors**: If you see 403 Forbidden errors when accessing the Kubernetes repositories, refer to the [Package Repository Documentation](package_repository.md) for solutions.

## [END LOCKED DOCUMENTATION] 