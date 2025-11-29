# VM Management & Provisioning Guide

## Overview

This document details the lifecycle management of Virtual Machines in the Kubernetes cluster, including provisioning strategies, configuration via `cloud-init`, network setup, and snapshot operations.

The primary tool for these operations is the `k8s-manager.sh` script.

## 1. Provisioning Strategy (Cloning)

We utilize a **"Golden Image"** cloning strategy based on official Ubuntu Cloud Images. This ensures consistency and speed.

### The Process
1.  **Base Image Acquisition**: The script downloads the official `Ubuntu 24.04 LTS (Noble Numbat)` Cloud Image (`.img` or `.iso`) to `base_images/`.
2.  **Disk Cloning**: For each new VM (e.g., `gateway1`, `k8s-master1`):
    *   A new VM directory is created (`VMs/k8s_cluster/<name>.vmwarevm`).
    *   The base image is converted and cloned into a fresh `.vmdk` disk using `qemu-img convert`.
    *   The disk is resized to the target size (default: 40GB).
3.  **VM Definition**: A custom `.vmx` file is generated defining CPU (2-4 vCPU), RAM (2-4GB), and network interfaces.

### Why this approach?
*   **Speed**: Cloning a disk image is faster than running a standard OS installer.
*   **Consistency**: Every VM starts from the exact same bit-for-bit OS state.
*   **Automation**: Completely scriptable without user intervention.

## 2. Configuration (Cloud-Init)

We use `cloud-init` to bootstrap the VMs on their first boot. This "personalizes" the cloned image.

### Configuration File
A `user-data` ISO is generated and attached to each VM. This configuration handles:

*   **Hostname**: Sets the unique hostname (e.g., `k8s-master1`).
*   **User Accounts**: Creates the `ubuntu` user and configures `sudo` access (passwordless).
*   **SSH Access**: Injects your local public key (`~/.ssh/id_ed25519.pub`) into `~/.ssh/authorized_keys`.
*   **Packages**: Installs essential tools:
    *   `open-vm-tools` (VMware integration)
    *   `qemu-guest-agent`
    *   `curl`, `wget`, `vim`
    *   `nginx` / `keepalived` (for Gateways)

### Customizing Cloud-Init
You can modify the templates in `templates/cloud-init-*.yaml` to change the default bootstrap configuration.

## 3. Network Setup

### Network Architecture
The cluster uses a **Dual-Homed DMZ** design with vmnet2 for internal cluster communication:

| VM Type | Interface | Network | IP Range |
|---------|-----------|---------|----------|
| Gateway | ens160 | Bridged (LAN) | 192.168.68.x |
| Gateway | ens192 | vmnet2 (Internal) | 10.10.0.x |
| K8s Node | ens160 | vmnet2 (Internal) | 10.10.0.x |

### Initial Boot (DHCP)
1.  On first boot, VMs request an IP address from the VMware Fusion DHCP server (vmnet2).
2.  The script waits for the VM to report an IP via `vmrun getGuestIPAddress`.
3.  This initial IP is captured and stored in `vm-ips.env`.

### vmnet2 Configuration
```
Network: 10.10.0.0/24
DHCP Range: 10.10.0.128 - 10.10.0.254
NAT Gateway: 10.10.0.2 (provides internet access)
Host IP: 10.10.0.1 (Mac)
```

### Static Configuration (Terraform)
While the VMs boot with DHCP, Terraform is configured to treat these IPs as stable resources.
*   **External VIP**: `192.168.68.210` on LAN (Keepalived on Gateways).
*   **Internal VIP**: `10.10.0.100` for K8s API endpoint.
*   **DNS**: The `systemd-resolved` configuration is managed to ensure consistent DNS resolution.

## 4. APT Package Caching

The environment includes a dedicated **APT Cache Server** for faster provisioning.

*   **Server VM**: `apt-cache-server`
*   **IP**: `10.10.0.148` (on vmnet2)
*   **Port**: `3142`
*   **Service**: `apt-cacher-ng`

### Current Status (2025-11-25)

✅ **Fully Operational**: The APT cache server has been migrated to **vmnet2** (10.10.0.0/24) and is now accessible to all K8s cluster VMs.

**Configuration**:
- All K8s VMs configured with APT proxy in `/etc/apt/apt.conf.d/01proxy`
- Cache storage: `/var/cache/apt-cacher-ng` (~314MB cached)
- Internet access via NAT gateway (10.10.0.2)

### Client Configuration
All VMs are configured with `/etc/apt/apt.conf.d/01proxy`:

```bash
Acquire::http::Proxy "http://10.10.0.148:3142";
```

### Verifying Cache Usage
Check apt-cacher-ng logs to confirm packages are being served from cache:
```bash
ssh ubuntu@10.10.0.148 'sudo tail -20 /var/log/apt-cacher-ng/apt-cacher.log'
```

## 5. Snapshot Management

Snapshots are critical for safe experimentation. The `k8s-manager.sh` script provides robust snapshot tools.

| Feature | Menu Option | Description |
|---------|-------------|-------------|
| **Create** | 4 | Creates a consistent snapshot across ALL cluster VMs simultaneously. |
| **List** | 5 | Displays a table of all snapshots and their status per VM. |
| **Rollback** | 6 | Reverts a specific VM (or all) to a previous state. |
| **Delete** | 7 | Removes snapshots to free up disk space. |

### Current Snapshots (2025-11-25)

All VMs have a clean, patched snapshot:

| VM | Snapshot Name | Description |
|----|---------------|-------------|
| gateway1 | `patched-20251125` | Fully patched Ubuntu 24.04 |
| gateway2 | `patched-20251125` | Fully patched Ubuntu 24.04 |
| k8s-master1 | `patched-20251125` | Fully patched Ubuntu 24.04 |
| k8s-master2 | `patched-20251125` | Fully patched Ubuntu 24.04 |
| k8s-master3 | `patched-20251125` | Fully patched Ubuntu 24.04 |
| k8s-worker1 | `patched-20251125` | Fully patched Ubuntu 24.04 |
| k8s-worker2 | `patched-20251125` | Fully patched Ubuntu 24.04 |

**Snapshot Policy**: Maintain only ONE snapshot per VM to conserve disk space. Delete old snapshots before creating new ones.

**Note on GUI Hangs**: VMware Fusion's `vmrun snapshot` command can sometimes hang when the GUI is open. The script includes a timeout mechanism to handle this safely in the background.

## 6. Removing VMs

To decommission the cluster:
*   **Option 8** in `k8s-manager.sh`: "Delete all VMs".
*   This performs a "Hard Stop", deletes the VM files from disk, and unregisters them from VMware Fusion.
*   It also cleans up `generated/` configs and Terraform state.