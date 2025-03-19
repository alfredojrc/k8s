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
cat > terraform.tfvars << EOF
# VM IP addresses
haproxy1_ip = "$(grep haproxy1_ip vm-ips.env | cut -d '"' -f 2)"
haproxy2_ip = "$(grep haproxy2_ip vm-ips.env | cut -d '"' -f 2)"
master1_ip = "$(grep master1_ip vm-ips.env | cut -d '"' -f 2)"
master2_ip = "$(grep master2_ip vm-ips.env | cut -d '"' -f 2)"
master3_ip = "$(grep master3_ip vm-ips.env | cut -d '"' -f 2)"
worker1_ip = "$(grep worker1_ip vm-ips.env | cut -d '"' -f 2)"
worker2_ip = "$(grep worker2_ip vm-ips.env | cut -d '"' -f 2)"

# Network configuration
virtual_ip = "10.10.0.100"
network_interface = "ens160"
pod_network_cidr = "10.244.0.0/16"
service_cidr = "10.96.0.0/12"

# SSH configuration
ssh_private_key_path = "~/.ssh/id_ed25519"
ssh_username = "ubuntu"

# Kubernetes configuration
kubernetes_version = "1.29.0"
cilium_version = "1.14.4"

# HAProxy configuration
haproxy_stats_credentials = "admin:admin"
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