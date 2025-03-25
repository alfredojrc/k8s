# Kubernetes Cluster on VMware Fusion

This repository contains scripts and Terraform configurations for deploying a high-availability Kubernetes cluster on VMware Fusion using Apple Silicon Macs.

## Architecture

The cluster consists of the following components:

- 2 HAProxy VMs with keepalived for high availability load balancing
- 3 Kubernetes master nodes for control plane redundancy
- 2 Kubernetes worker nodes for running workloads
- Cilium CNI for networking and network policy

## Project Structure

```
.
├── README.md                  # Main documentation
├── main.tf                    # Main Terraform configuration
├── variables.tf               # Terraform variables
├── outputs.tf                 # Terraform outputs
├── terraform.tfvars           # Default values for Terraform variables
├── k8s-manager.sh             # All-in-one script for cluster management
├── terraform-setup.sh         # Script to set up Terraform configuration
├── templates/                 # Template files for configurations
│   ├── haproxy.cfg.tpl        # HAProxy configuration template
│   └── keepalived.conf.tpl    # Keepalived configuration template
├── generated/                 # Generated configuration files
└── base_images/               # Directory for Ubuntu cloud images
```

## Deployment Process

The deployment process is now simplified with a single all-in-one script (`k8s-manager.sh`) that provides an interactive menu for all operations:

1. VM creation and management
2. Snapshot handling
3. Service configuration using Terraform
4. Kubernetes deployment

## All-in-One Management Interface

The project includes a new consolidated script that combines all functionality in a single executable. Run it with:

```bash
./k8s-manager.sh
```

The menu provides the following options:

1. **Deploy Kubernetes Cluster (Full Workflow)** - Runs the complete deployment process
2. **Create all VMs and basic configuration** - Creates a new set of VMs for the Kubernetes cluster
3. **Check VM status and network configuration** - Verifies the status and network configuration of all VMs
4. **Create snapshots of all VMs** - Creates snapshots of all VMs (useful before making changes)
5. **List snapshots for all VMs** - Shows all available snapshots
6. **Rollback to a snapshot** - Allows you to revert VMs to a previous snapshot
7. **Delete all snapshots** - Removes all snapshots to save disk space
8. **Delete all VMs** - Completely removes all VMs in the cluster
9. **Deploy Kubernetes on existing VMs** - Runs only the Kubernetes deployment part on existing VMs
0. **Exit** - Exits the script

### VM Creation

The script creates the following VMs for the Kubernetes cluster:

- haproxy1 & haproxy2: Load balancer VMs with 2GB RAM and 2 CPUs
- k8s-master1, k8s-master2, k8s-master3: Control plane nodes with 4GB RAM and 4 CPUs
- k8s-worker1 & k8s-worker2: Worker nodes with 4GB RAM and 4 CPUs

### Service Configuration

Terraform is used to configure all the services on the VMs:

- HAProxy and keepalived on the HAProxy VMs
  - Configures a virtual IP (10.10.0.100) for high availability
  - Sets up load balancing for the Kubernetes API server
  - Configures HTTP/HTTPS traffic routing to worker nodes

- Kubernetes on the master and worker nodes
  - Installs containerd as the container runtime
  - Configures the Kubernetes control plane on master nodes
  - Joins worker nodes to the cluster

- Cilium CNI for networking
  - Provides networking between pods
  - Implements Kubernetes Network Policies
  - Offers enhanced observability with Hubble

## Prerequisites

- VMware Fusion Pro 13 or later on Apple Silicon Mac
- Ubuntu 24.04 LTS (Noble Numbat) ARM64 cloud image in the `base_images` directory
- Terraform 1.5.0 or later
- SSH key pair for authentication (default: ~/.ssh/id_ed25519)
- At least 50GB of free disk space
- 16GB+ RAM recommended

## Quick Start

1. Clone this repository:
   ```bash
   git clone <repository-url>
   cd k8s
   ```

2. Make the management script executable:
   ```bash
   chmod +x k8s-manager.sh
   ```

3. Run the management script:
   ```bash
   ./k8s-manager.sh
   ```

4. Select option 1 from the menu to run the full deployment workflow.

5. After deployment, you can access the Kubernetes cluster using:
   ```bash
   # SSH to the first master node
   ssh ubuntu@$(grep master1_ip vm-ips.env | cut -d '"' -f 2)

   # Check cluster status
   kubectl get nodes -o wide
   kubectl get pods -A
   ```

## VM Snapshot Management

The consolidated script allows you to create and manage snapshots:

### Creating Snapshots

1. Run the management script:
   ```bash
   ./k8s-manager.sh
   ```
2. Choose option 4 to create snapshots of all VMs
3. Enter a name for the snapshot when prompted

### Rolling Back to a Snapshot

If you need to restore VMs to a previous state:

1. Run the management script
2. Choose option 6 to rollback to a snapshot
3. Select the VM and then the snapshot you want to restore

## Accessing the Cluster

After deployment, you can access the Kubernetes cluster using:

```bash
# SSH to the first master node
ssh ubuntu@$(grep master1_ip vm-ips.env | cut -d '"' -f 2)

# Check cluster status
kubectl get nodes -o wide
kubectl get pods -A
```

The HAProxy statistics page is available at:
```
http://10.10.0.100:9000
```
(using the credentials admin:admin)

## Configuration

The Terraform configuration can be customized by modifying the `terraform.tfvars` file:

- VM IP addresses
- Network configuration (virtual IP, network interface)
- SSH configuration (key path, username)
- Kubernetes version
- Cilium version and configuration
- HAProxy settings

## Troubleshooting

### VM Creation Issues

- Ensure VMware Fusion is properly installed and licensed
- Check that the base image exists and is accessible
- Verify you have sufficient disk space and memory

### VM Network Issues

- Use option 3 in the menu to check VM network configuration
- Verify that all VMs have valid IP addresses
- Ensure the VMs can communicate with each other

### Kubernetes Deployment Issues

- Check that all VMs are running and accessible via SSH
- Verify the HAProxy configuration is correct
- Ensure the virtual IP is properly configured
- Check the Kubernetes logs on the master nodes

## Cleanup

To clean up the resources:

1. Run the management script:
   ```bash
   ./k8s-manager.sh
   ```
2. Choose option 8 to delete all VMs