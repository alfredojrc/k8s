#!/bin/bash

# Script to create all VMs for the Kubernetes cluster
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# [LOCKED_CONFIG: Do not modify these configurations]
# Configuration
BASE_IMAGE="$HOME/godz/k8s/base_images/noble-server-cloudimg-arm64.img"
# Use password from password file instead of hardcoding it
PASSWORD_FILE="$HOME/.k8s_password"
if [ -f "$PASSWORD_FILE" ]; then
    PASSWORD=$(cat "$PASSWORD_FILE")
else
    # Generate a random password if file doesn't exist
    PASSWORD=$(openssl rand -base64 12)
    echo "$PASSWORD" > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
fi
VM_CLUSTER_DIR="$HOME/Virtual Machines.localized/k8s_cluster"
CREATE_VM_SCRIPT="./create-ubuntu-vm.sh"
# [END_LOCKED_CONFIG]

# Check if base image exists
if [ ! -f "$BASE_IMAGE" ]; then
    echo -e "${RED}Error: Base image not found at $BASE_IMAGE${NC}"
    exit 1
fi

# Check if create-ubuntu-vm.sh exists and is executable
if [ ! -x "$CREATE_VM_SCRIPT" ]; then
    echo -e "${RED}Error: $CREATE_VM_SCRIPT not found or not executable${NC}"
        exit 1
    fi
    
# [LOCKED_FUNCTION: Do not modify the create_vm function]
# Create VM function
create_vm() {
    local vm_name=$1
    local memory=$2
    local cpus=$3
    local hostname=$4

    echo -e "\n${YELLOW}Creating VM: $vm_name${NC}"
    
    # Modify create-ubuntu-vm.sh to use the specified VM name and password
    sed -i '' "s/VM_NAME=\"[^\"]*\"/VM_NAME=\"$vm_name\"/" "$CREATE_VM_SCRIPT"
    sed -i '' "s/VM_MEMORY=[0-9]*/VM_MEMORY=$memory/" "$CREATE_VM_SCRIPT"
    sed -i '' "s/VM_CPUS=[0-9]*/VM_CPUS=$cpus/" "$CREATE_VM_SCRIPT"
    
    # Create the VM
    $CREATE_VM_SCRIPT
    
    # Wait for VM to boot and get IP address
    echo -e "${YELLOW}Waiting for $vm_name to boot and get an IP address...${NC}"
    local vm_ip=""
    local vmx_path="$VM_CLUSTER_DIR/$vm_name.vmwarevm/$vm_name.vmx"
    
    # Start the VM if it's not already running
    if ! vmrun -T fusion list | grep -q "$vmx_path"; then
        echo -e "${YELLOW}Starting $vm_name...${NC}"
        vmrun -T fusion start "$vmx_path"
    fi
    
    # Get the IP address
    vm_ip=$(vmrun -T fusion getGuestIPAddress "$vmx_path" -wait)
    echo -e "${GREEN}$vm_name IP address: $vm_ip${NC}"
    
    # Wait for SSH to be available
    echo -e "${YELLOW}Waiting for SSH on $vm_name to be available...${NC}"
    while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$vm_ip "echo SSH connection successful" &>/dev/null; do
        echo -e "${YELLOW}Waiting for SSH on $vm_name...${NC}"
        sleep 5
    done
    echo -e "${GREEN}SSH connection to $vm_name successful${NC}"
    
    # Install basic packages
    echo -e "${YELLOW}Installing basic packages on $vm_name...${NC}"
    ssh -o StrictHostKeyChecking=no ubuntu@$vm_ip "sudo apt-get update && sudo apt-get install -y neovim tmux bash-completion curl wget htop net-tools"
    
    # Return the IP address
    echo "$vm_ip"
}
# [END_LOCKED_FUNCTION]

# Create directory for VM IPs
mkdir -p generated

# Create empty vm-ips.env file first
rm -f vm-ips.env
touch vm-ips.env

# [LOCKED_VM_CREATION: Do not modify the VM creation sequence]
# Create HAProxy VMs
echo -e "${YELLOW}Creating HAProxy VMs...${NC}"
haproxy1_ip=$(create_vm "haproxy1" 2048 2 "haproxy1")
echo "haproxy1_ip = \"$haproxy1_ip\"" >> vm-ips.env

haproxy2_ip=$(create_vm "haproxy2" 2048 2 "haproxy2")
echo "haproxy2_ip = \"$haproxy2_ip\"" >> vm-ips.env

# Create Kubernetes master nodes
echo -e "${YELLOW}Creating Kubernetes master nodes...${NC}"
master1_ip=$(create_vm "k8s-master1" 4096 4 "k8s-master1")
echo "master1_ip = \"$master1_ip\"" >> vm-ips.env

master2_ip=$(create_vm "k8s-master2" 4096 4 "k8s-master2")
echo "master2_ip = \"$master2_ip\"" >> vm-ips.env

master3_ip=$(create_vm "k8s-master3" 4096 4 "k8s-master3")
echo "master3_ip = \"$master3_ip\"" >> vm-ips.env

# Create Kubernetes worker nodes
echo -e "${YELLOW}Creating Kubernetes worker nodes...${NC}"
worker1_ip=$(create_vm "k8s-worker1" 4096 4 "k8s-worker1")
echo "worker1_ip = \"$worker1_ip\"" >> vm-ips.env

worker2_ip=$(create_vm "k8s-worker2" 4096 4 "k8s-worker2")
echo "worker2_ip = \"$worker2_ip\"" >> vm-ips.env
# [END_LOCKED_VM_CREATION]

echo -e "\n${GREEN}All VMs created successfully!${NC}"
echo -e "${GREEN}VM IPs saved to vm-ips.env${NC}"
echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "1. Run 'terraform init' to initialize Terraform"
echo -e "2. Run 'terraform apply' to configure the Kubernetes cluster"
echo -e "\n${YELLOW}You can SSH into the VMs using:${NC}"
echo -e "ssh ubuntu@<vm-ip>"
echo -e "\n${YELLOW}VM IPs:${NC}"
cat vm-ips.env | sed 's/ = /: /g' 