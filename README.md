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
├── create-ubuntu-vm.sh        # Script to create a single Ubuntu VM
├── create-vms.sh              # Script to create all VMs for the cluster
├── terraform-setup.sh         # Script to set up Terraform configuration
├── templates/                 # Template files for configurations
│   ├── haproxy.cfg.tpl        # HAProxy configuration template
│   └── keepalived.conf.tpl    # Keepalived configuration template
├── generated/                 # Generated configuration files
└── base_images/               # Directory for Ubuntu cloud images
```

## Deployment Process

The deployment process is split into two parts:

1. VM creation using shell scripts
2. Service configuration using Terraform

### VM Creation

The `create-vms.sh` script creates all the VMs required for the Kubernetes cluster:

- haproxy1 & haproxy2: Load balancer VMs with 2GB RAM and 2 CPUs
- k8s-master1, k8s-master2, k8s-master3: Control plane nodes with 4GB RAM and 4 CPUs
- k8s-worker1 & k8s-worker2: Worker nodes with 4GB RAM and 4 CPUs

The script also saves the IP addresses of the VMs to a file named `vm-ips.env` for use with Terraform.

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

## Deployment Steps

### 1. Prepare the Base Image

Ensure you have the Ubuntu cloud image in the base_images directory:

```bash
mkdir -p base_images
cd base_images
wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img
cd ..
```

### 2. Create VMs

Run the `create-vms.sh` script to create all the VMs:

```bash
./create-vms.sh
```

This script will:
- Create all the necessary VMs
- Wait for them to boot and get IP addresses
- Install basic packages on each VM
- Save the VM IPs to vm-ips.env

### 3. Set Up Terraform

Run the `terraform-setup.sh` script to prepare the Terraform configuration:

```bash
./terraform-setup.sh
```

This script will:
- Create a terraform.tfvars file with the VM IPs and configuration
- Initialize Terraform

### 4. Deploy Kubernetes with Terraform

Apply the Terraform configuration to deploy Kubernetes:

```bash
terraform apply
```

This will:
- Configure HAProxy and keepalived for load balancing
- Install and configure Kubernetes on all nodes
- Set up the Cilium CNI for networking
- Verify the cluster is working properly

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

### Kubernetes Deployment Issues

- Check that all VMs are running and accessible via SSH
- Verify the HAProxy configuration is correct
- Ensure the virtual IP is properly configured
- Check the Kubernetes logs on the master nodes

## Cleanup

To clean up the resources:

### 1. Destroy Terraform Resources

```bash
terraform destroy
```

### 2. Delete the VMs

```bash
# Stop all VMs
vmrun -T fusion stop "~/Virtual Machines.localized/k8s_cluster/haproxy1.vmwarevm/haproxy1.vmx"
vmrun -T fusion stop "~/Virtual Machines.localized/k8s_cluster/haproxy2.vmwarevm/haproxy2.vmx"
vmrun -T fusion stop "~/Virtual Machines.localized/k8s_cluster/k8s-master1.vmwarevm/k8s-master1.vmx"
vmrun -T fusion stop "~/Virtual Machines.localized/k8s_cluster/k8s-master2.vmwarevm/k8s-master2.vmx"
vmrun -T fusion stop "~/Virtual Machines.localized/k8s_cluster/k8s-master3.vmwarevm/k8s-master3.vmx"
vmrun -T fusion stop "~/Virtual Machines.localized/k8s_cluster/k8s-worker1.vmwarevm/k8s-worker1.vmx"
vmrun -T fusion stop "~/Virtual Machines.localized/k8s_cluster/k8s-worker2.vmwarevm/k8s-worker2.vmx"

# Remove VM directory
rm -rf "~/Virtual Machines.localized/k8s_cluster"
```

### 3. Remove Redundant Files

If you want to clean up redundant files in the project, you can use the provided cleanup script:

```bash
./cleanup-redundant-files.sh
```

This script removes unnecessary files and directories while keeping the essential ones for the deployment process.

## Project Maintenance

### Essential Files

The following files and directories are essential for the deployment process:

- **VM Creation**:
  - `create-ubuntu-vm.sh`: Script to create a single Ubuntu VM
  - `create-vms.sh`: Script to create all VMs for the cluster
  - `base_images/`: Directory for Ubuntu cloud images

- **Terraform Configuration**:
  - `terraform-setup.sh`: Script to set up Terraform configuration
  - `main.tf`: Main Terraform configuration
  - `variables.tf`: Terraform variables
  - `outputs.tf`: Terraform outputs
  - `templates/`: Directory containing configuration templates
  - `generated/`: Directory for generated configuration files

### Scripts Directory

The `scripts` directory contains utility scripts:

- `download_base_image.sh`: Script to download the Ubuntu cloud image

### Cleanup Script

The `cleanup-redundant-files.sh` script helps maintain a clean project structure by removing unnecessary files and directories.