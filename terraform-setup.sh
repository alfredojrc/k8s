#!/bin/bash

# Script to set up Terraform for managing the Kubernetes cluster
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Setting up Terraform for Kubernetes cluster management${NC}"

# Check if vm-ips.env exists
if [ ! -f "vm-ips.env" ]; then
  echo -e "${RED}Error: vm-ips.env file not found${NC}"
  echo -e "${YELLOW}Please run create-vms.sh first to create the VMs and generate the vm-ips.env file${NC}"
  exit 1
fi

# Create terraform.tfvars file
echo -e "${YELLOW}Creating terraform.tfvars file${NC}"
cat vm-ips.env > terraform.tfvars
cat >> terraform.tfvars << EOF

# Network configuration
virtual_ip = "192.168.68.210"
network_interface = "ens160"
pod_network_cidr = "10.244.0.0/16"
service_cidr = "10.96.0.0/12"

# SSH configuration
ssh_private_key_path = "~/.ssh/id_ed25519"
ssh_username = "ubuntu"

# Kubernetes configuration
kubernetes_version = "1.31.0"
cilium_version = "1.16.1"

# Gateway configuration
gateway_stats_credentials = "admin:admin"

# APT Proxy
apt_proxy_url = "${K8S_APT_CACHE_SERVER_IP:+http://$K8S_APT_CACHE_SERVER_IP:3142}"
EOF

echo -e "${GREEN}terraform.tfvars file created successfully${NC}"

# Create directories
mkdir -p generated templates

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform${NC}"
terraform init

echo -e "${GREEN}Terraform setup completed successfully${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Review and modify terraform.tfvars if needed"
echo -e "2. Run 'terraform plan' to see what changes will be made"
echo -e "3. Run 'terraform apply' to apply the changes" 