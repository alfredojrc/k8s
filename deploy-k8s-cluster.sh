#!/bin/bash

# Comprehensive script to deploy a Kubernetes cluster on VMware Fusion
# This script handles:
# 1. Removing existing VMs
# 2. Creating necessary directories
# 3. Downloading the base image if needed
# 4. Creating new VMs
# 5. Setting up Terraform
# 6. Deploying Kubernetes

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# [LOCKED_CONFIG: Do not modify these critical settings]
# Configuration
BASE_IMAGE_PATH="$HOME/godz/k8s/base_images/noble-server-cloudimg-arm64.img"
BASE_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img"
VM_CLUSTER_DIR="$HOME/Virtual Machines.localized/k8s_cluster"
PROJECT_DIR="$HOME/godz/k8s"
# Use a more secure approach for password
PASSWORD_FILE="$HOME/.k8s_password"
# [END_LOCKED_CONFIG]

# Function to print section headers
print_header() {
    echo -e "\n${BLUE}=========================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================================${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# [LOCKED_FUNCTION: Do not modify the prerequisites check]
# Function to check prerequisites
check_prerequisites() {
    print_header "Checking prerequisites"
    
    # Check if VMware Fusion is installed
    if ! command_exists vmrun; then
        echo -e "${RED}Error: vmrun command not found. Please ensure VMware Fusion is installed and in your PATH.${NC}"
        echo -e "${YELLOW}You may need to add the following to your .zshrc or .bashrc:${NC}"
        echo -e "export PATH=\$PATH:\"/Applications/VMware Fusion.app/Contents/Public\""
        exit 1
    fi
    
    # Check if qemu-img is installed
    if ! command_exists qemu-img; then
        echo -e "${RED}Error: qemu-img not found. Please install it using Homebrew:${NC}"
        echo -e "brew install qemu"
        exit 1
    fi
    
    # Check if mkisofs is installed
    if ! command_exists mkisofs; then
        echo -e "${RED}Error: mkisofs not found. Please install it using Homebrew:${NC}"
        echo -e "brew install cdrtools"
        exit 1
    fi
    
    # Check if Terraform is installed
    if ! command_exists terraform; then
        echo -e "${RED}Error: terraform not found. Please install it using Homebrew:${NC}"
        echo -e "brew install terraform"
        exit 1
    fi
    
    # Check if SSH key exists
    if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
        echo -e "${RED}Error: SSH key not found at $HOME/.ssh/id_ed25519${NC}"
        echo -e "${YELLOW}Please create an SSH key pair using:${NC}"
        echo -e "ssh-keygen -t ed25519"
        exit 1
    fi
    
    # Check if required scripts exist
    if [ ! -x "./create-vms.sh" ]; then
        echo -e "${RED}Error: create-vms.sh not found or not executable${NC}"
        exit 1
    fi
    
    if [ ! -x "./terraform-setup.sh" ]; then
        echo -e "${RED}Error: terraform-setup.sh not found or not executable${NC}"
        exit 1
    fi
    
    if [ ! -x "./create-ubuntu-vm.sh" ]; then
        echo -e "${RED}Error: create-ubuntu-vm.sh not found or not executable${NC}"
        exit 1
    fi
    
    # Check if required Terraform files exist
    if [ ! -f "./main.tf" ]; then
        echo -e "${RED}Error: main.tf not found${NC}"
        exit 1
    fi
    
    if [ ! -f "./variables.tf" ]; then
        echo -e "${RED}Error: variables.tf not found${NC}"
        exit 1
    fi
    
    if [ ! -f "./outputs.tf" ]; then
        echo -e "${RED}Error: outputs.tf not found${NC}"
        exit 1
    fi
    
    # Check if required template files exist
    if [ ! -f "./templates/haproxy.cfg.tpl" ]; then
        echo -e "${RED}Error: templates/haproxy.cfg.tpl not found${NC}"
        exit 1
    fi
    
    if [ ! -f "./templates/keepalived.conf.tpl" ]; then
        echo -e "${RED}Error: templates/keepalived.conf.tpl not found${NC}"
        exit 1
    fi
    
    # Check or create password file
    if [ ! -f "$PASSWORD_FILE" ]; then
        echo -e "${YELLOW}Password file not found. Creating a secure password...${NC}"
        # Generate a random password and save it to the file
        openssl rand -base64 12 > "$PASSWORD_FILE"
        chmod 600 "$PASSWORD_FILE"
        echo -e "${GREEN}Password file created at $PASSWORD_FILE${NC}"
    else
        chmod 600 "$PASSWORD_FILE"
    fi
    
    # Check if documentation exists
    if [ ! -f "./docs/vm_deployment.md" ]; then
        echo -e "${YELLOW}Warning: Documentation file not found at ./docs/vm_deployment.md${NC}"
        echo -e "${YELLOW}It is recommended to read the documentation before proceeding.${NC}"
    else
        echo -e "${GREEN}Found VM deployment documentation at ./docs/vm_deployment.md${NC}"
        echo -e "${YELLOW}Please review this document for important information about the VM deployment process.${NC}"
    fi
    
    echo -e "${GREEN}All prerequisites are met.${NC}"
}
# [END_LOCKED_FUNCTION]

# Function to remove existing VMs
remove_existing_vms() {
    print_header "Removing existing VMs"
    
    # Get list of running VMs
    RUNNING_VMS=$(vmrun -T fusion list | grep -v "Total running VMs" | grep "$VM_CLUSTER_DIR" || true)
    
    if [ -n "$RUNNING_VMS" ]; then
        echo -e "${YELLOW}Found running VMs:${NC}"
        echo "$RUNNING_VMS"
        
        # Stop each running VM
        echo -e "${YELLOW}Stopping running VMs...${NC}"
        echo "$RUNNING_VMS" | while read -r VM_PATH; do
            if [ -n "$VM_PATH" ]; then
                VM_NAME=$(basename "$(dirname "$VM_PATH")" | sed 's/\.vmwarevm//')
                echo -e "${YELLOW}Stopping VM: $VM_NAME${NC}"
                vmrun -T fusion stop "$VM_PATH" soft || true
                sleep 2
            fi
        done
    else
        echo -e "${GREEN}No running VMs found.${NC}"
    fi
    
    # Remove VM directory if it exists
    if [ -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${YELLOW}Removing VM directory: $VM_CLUSTER_DIR${NC}"
        rm -rf "$VM_CLUSTER_DIR"
    else
        echo -e "${GREEN}VM directory does not exist: $VM_CLUSTER_DIR${NC}"
    fi
    
    # Clean up VM-related files
    echo -e "${YELLOW}Cleaning up VM-related files...${NC}"
    cd "$PROJECT_DIR"
    
    # Remove vm-ips.env if it exists
    if [ -f "vm-ips.env" ]; then
        rm -f "vm-ips.env"
        echo -e "${GREEN}Removed vm-ips.env${NC}"
    fi
    
    # Remove generated directory if it exists
    if [ -d "generated" ]; then
        rm -rf "generated"
        echo -e "${GREEN}Removed generated directory${NC}"
    else
        mkdir -p "generated"
        echo -e "${GREEN}Created generated directory${NC}"
    fi
    
    # Remove Terraform state files if they exist
    if [ -f "terraform.tfstate" ] || [ -f "terraform.tfstate.backup" ]; then
        rm -f terraform.tfstate terraform.tfstate.backup
        echo -e "${GREEN}Removed Terraform state files${NC}"
    fi
    
    echo -e "${GREEN}All VMs and related files have been removed.${NC}"
}

# [LOCKED_FUNCTION: Do not modify the base image download process]
# Function to download base image if needed
download_base_image() {
    print_header "Checking base image"
    
    # Create base_images directory if it doesn't exist
    mkdir -p "$(dirname "$BASE_IMAGE_PATH")"
    
    # Check if base image exists
    if [ ! -f "$BASE_IMAGE_PATH" ]; then
        echo -e "${YELLOW}Base image not found. Downloading...${NC}"
        echo -e "${YELLOW}Downloading Ubuntu 24.04 LTS ARM64 cloud image...${NC}"
        curl -L "$BASE_IMAGE_URL" -o "$BASE_IMAGE_PATH"
        
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Successfully downloaded base image to $BASE_IMAGE_PATH${NC}"
        else
            echo -e "${RED}Failed to download base image${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}Base image already exists at $BASE_IMAGE_PATH${NC}"
    fi
}
# [END_LOCKED_FUNCTION]

# [LOCKED_FUNCTION: Do not modify the VM creation process]
# Function to create VMs
create_vms() {
    print_header "Creating VMs"
    
    # Create VM cluster directory
    mkdir -p "$VM_CLUSTER_DIR"
    
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Update password in create-ubuntu-vm.sh
    PASSWORD=$(cat "$PASSWORD_FILE")
    sed -i '' "s|PASSWORD=.*|PASSWORD=\"$PASSWORD\"|" "./create-ubuntu-vm.sh"
    
    # Run create-vms.sh
    echo -e "${YELLOW}Running create-vms.sh to create VMs...${NC}"
    ./create-vms.sh
    
    # Check if vm-ips.env was created
    if [ ! -f "vm-ips.env" ]; then
        echo -e "${RED}Error: vm-ips.env not created. VM creation may have failed.${NC}"
        exit 1
    fi
    
    # Verify that all VMs were created successfully by checking vm-ips.env
    required_vms=("haproxy1_ip" "haproxy2_ip" "master1_ip" "master2_ip" "master3_ip" "worker1_ip" "worker2_ip")
    for vm in "${required_vms[@]}"; do
        if ! grep -q "$vm" vm-ips.env; then
            echo -e "${RED}Error: $vm not found in vm-ips.env. VM creation may have failed.${NC}"
            exit 1
        fi
        
        # Check if the IP is valid
        ip=$(grep "$vm" vm-ips.env | cut -d '"' -f 2)
        if [[ ! $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo -e "${RED}Error: Invalid IP address for $vm: $ip${NC}"
            exit 1
        fi
    done
    
    echo -e "${GREEN}VMs created successfully.${NC}"
}
# [END_LOCKED_FUNCTION]

# Function to set up Terraform
setup_terraform() {
    print_header "Setting up Terraform"
    
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Run terraform-setup.sh
    echo -e "${YELLOW}Running terraform-setup.sh to set up Terraform...${NC}"
    ./terraform-setup.sh
    
    # Verify terraform.tfvars was created
    if [ ! -f "terraform.tfvars" ]; then
        echo -e "${RED}Error: terraform.tfvars not created. Terraform setup may have failed.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Terraform setup completed successfully.${NC}"
}

# Function to deploy Kubernetes
deploy_kubernetes() {
    print_header "Deploying Kubernetes"
    
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Run terraform plan first to check for errors
    echo -e "${YELLOW}Running terraform plan to check for errors...${NC}"
    terraform plan
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: terraform plan failed. Please check the errors above.${NC}"
        exit 1
    fi
    
    # Run terraform apply
    echo -e "${YELLOW}Running terraform apply to deploy Kubernetes...${NC}"
    terraform apply -auto-approve
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: terraform apply failed. Please check the errors above.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Kubernetes deployment completed successfully.${NC}"
}

# Function to display cluster information
display_cluster_info() {
    print_header "Kubernetes Cluster Information"
    
    # Extract master1 IP from vm-ips.env
    MASTER1_IP=$(grep master1_ip vm-ips.env | cut -d '"' -f 2)
    
    echo -e "${GREEN}Kubernetes cluster has been deployed successfully!${NC}"
    echo -e "\n${YELLOW}Cluster Information:${NC}"
    echo -e "Virtual IP (HAProxy): 10.10.0.100"
    echo -e "HAProxy Stats: http://10.10.0.100:9000 (admin:admin)"
    echo -e "Master Node 1: $MASTER1_IP"
    echo -e "\n${YELLOW}To access the cluster:${NC}"
    echo -e "ssh ubuntu@$MASTER1_IP"
    echo -e "\n${YELLOW}To check cluster status:${NC}"
    echo -e "kubectl get nodes -o wide"
    echo -e "kubectl get pods -A"
    
    # Display password information
    echo -e "\n${YELLOW}VM Password Information:${NC}"
    echo -e "The VM password is stored securely in: $PASSWORD_FILE"
    echo -e "You can view it with: cat $PASSWORD_FILE"
}

# Function to verify connectivity to VMs
verify_connectivity() {
    print_header "Verifying connectivity to VMs"
    
    # Load VM IPs from vm-ips.env
    source <(cat vm-ips.env | sed 's/ = /=/g')
    
    # Array of VM IPs and names
    declare -A vm_ips
    vm_ips["HAProxy1"]=$haproxy1_ip
    vm_ips["HAProxy2"]=$haproxy2_ip
    vm_ips["Master1"]=$master1_ip
    vm_ips["Master2"]=$master2_ip
    vm_ips["Master3"]=$master3_ip
    vm_ips["Worker1"]=$worker1_ip
    vm_ips["Worker2"]=$worker2_ip
    
    # Check connectivity to each VM
    for vm_name in "${!vm_ips[@]}"; do
        vm_ip=${vm_ips[$vm_name]}
        echo -e "${YELLOW}Checking connectivity to $vm_name ($vm_ip)...${NC}"
        
        if ping -c 1 -W 2 "$vm_ip" &>/dev/null; then
            echo -e "${GREEN}$vm_name is reachable.${NC}"
        else
            echo -e "${RED}Warning: $vm_name is not reachable. This may cause issues with deployment.${NC}"
            echo -e "${YELLOW}Do you want to continue anyway? (y/n)${NC}"
            read -p "" -n 1 -r
            echo
            
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo -e "${RED}Deployment cancelled.${NC}"
                exit 1
            fi
        fi
    done
    
    echo -e "${GREEN}Connectivity verification completed.${NC}"
}

# Main function
main() {
    print_header "Kubernetes Cluster Deployment"
    
    # Display a notice about documentation
    echo -e "${YELLOW}IMPORTANT:${NC}"
    echo -e "This script deploys a Kubernetes cluster on VMware Fusion."
    echo -e "Please read the documentation in ./docs/vm_deployment.md before proceeding."
    echo -e "It contains important information about the VM deployment process."
    echo -e "Critical sections of the scripts are marked as [LOCKED] and should not be modified."
    echo -e ""
    
    # Check prerequisites
    check_prerequisites
    
    # Ask for confirmation
    echo -e "${YELLOW}This script will:${NC}"
    echo -e "1. Remove any existing Kubernetes VMs"
    echo -e "2. Create new VMs for the Kubernetes cluster"
    echo -e "3. Set up Terraform"
    echo -e "4. Deploy Kubernetes"
    echo -e "\n${RED}WARNING: This will delete any existing VMs in $VM_CLUSTER_DIR${NC}"
    echo -e "${YELLOW}Do you want to continue? (y/n)${NC}"
    read -p "" -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Deployment cancelled.${NC}"
        exit 1
    fi
    
    # Remove existing VMs
    remove_existing_vms
    
    # Download base image if needed
    download_base_image
    
    # Create VMs
    create_vms
    
    # Verify connectivity to VMs
    verify_connectivity
    
    # Set up Terraform
    setup_terraform
    
    # Ask for confirmation before deploying Kubernetes
    echo -e "${YELLOW}VMs have been created and Terraform has been set up.${NC}"
    echo -e "${YELLOW}Do you want to proceed with deploying Kubernetes? (y/n)${NC}"
    read -p "" -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Kubernetes deployment skipped. You can deploy it later by running:${NC}"
        echo -e "terraform apply"
        exit 0
    fi
    
    # Deploy Kubernetes
    deploy_kubernetes
    
    # Display cluster information
    display_cluster_info
}

# Run main function
main 