#!/bin/bash
# Consolidated K8s Manager Script
# This script provides a unified interface for managing a Kubernetes cluster on VMware Fusion
# It combines functionality from:
# - deploy-k8s-cluster.sh
# - create-vms.sh
# - create-ubuntu-vm.sh
# - validate_vm_config.sh

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

# VM Creation Configuration
BASE_IMAGE="$HOME/godz/k8s/base_images/noble-server-cloudimg-arm64.img"
VM_DISK_SIZE=40G

# VM Template Configuration
SSH_PUBLIC_KEY="$HOME/.ssh/id_ed25519.pub"

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

# [LOCKED_DISK_CREATION: Do not modify the disk creation process]
# Function to create a VM disk
create_vm_disk() {
    local VM_DIR=$1
    local VM_NAME=$2
    local VM_DISK="$VM_DIR/$VM_NAME.vmdk"
    
    echo -e "${YELLOW}Creating VM disk from base image...${NC}"
    # First convert to qcow2 format (better handling of conversion)
    TEMP_QCOW2="$VM_DIR/temp_disk.qcow2"
    echo -e "${YELLOW}Converting raw image to qcow2 format...${NC}"
    qemu-img convert -f raw -O qcow2 "$BASE_IMAGE" "$TEMP_QCOW2"

    # Resize the qcow2 image
    echo -e "${YELLOW}Resizing disk image to $VM_DISK_SIZE...${NC}"
    qemu-img resize "$TEMP_QCOW2" $VM_DISK_SIZE

    # Convert qcow2 to vmdk for VMware
    echo -e "${YELLOW}Converting to vmdk format...${NC}"
    qemu-img convert -f qcow2 -O vmdk "$TEMP_QCOW2" "$VM_DISK"

    # Remove temporary file
    rm -f "$TEMP_QCOW2"
}
# [END_LOCKED_DISK_CREATION]

# Function to create cloud-init ISO for a VM
create_cloud_init_iso() {
    local VM_DIR=$1
    local VM_NAME=$2
    local PASSWORD=$3
    local CLOUD_INIT_ISO="$VM_DIR/$VM_NAME-cloud-init.iso"
    
    echo -e "${YELLOW}Creating cloud-init configuration...${NC}"

    # Create meta-data file
    cat > "$VM_DIR/meta-data" << EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

    # Create user-data file
    cat > "$VM_DIR/user-data" << EOF
#cloud-config
hostname: $VM_NAME
fqdn: $VM_NAME.local
manage_etc_hosts: true
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    # Password is $PASSWORD
    passwd: $(openssl passwd -6 "$PASSWORD")
    ssh_authorized_keys:
      - $(cat "$SSH_PUBLIC_KEY")
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - net-tools
  - curl
  - wget
  - vim
  - htop
  - tmux
  - bash-completion
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "ubuntu:$PASSWORD" | chpasswd
  - echo "PermitRootLogin no" >> /etc/ssh/sshd_config
  - echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
  - systemctl restart sshd
power_state:
  mode: reboot
  timeout: 30
  condition: True
EOF

    # Create network-config file
    cat > "$VM_DIR/network-config" << EOF
version: 2
ethernets:
  ens160:
    dhcp4: true
    dhcp6: false
EOF

    # Create cloud-init ISO
    echo -e "${YELLOW}Creating cloud-init ISO...${NC}"
    mkisofs -output "$CLOUD_INIT_ISO" -volid cidata -joliet -rock "$VM_DIR/user-data" "$VM_DIR/meta-data" "$VM_DIR/network-config"
}

# [LOCKED_VMX: Do not modify the VMX file structure]
# Function to create VMX file for a VM
create_vmx_file() {
    local VM_DIR=$1
    local VM_NAME=$2
    local VM_MEMORY=$3
    local VM_CPUS=$4
    local VMX_FILE="$VM_DIR/$VM_NAME.vmx"
    
    echo -e "${YELLOW}Creating VMX file...${NC}"
    cat > "$VMX_FILE" << EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
numvcpus = "$VM_CPUS"
memsize = "$VM_MEMORY"
displayName = "$VM_NAME"
guestOS = "arm-ubuntu-64"
mks.enable3d = "FALSE"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
vmci0.present = "TRUE"
hpet0.present = "TRUE"
sata0.present = "TRUE"
nvme0.present = "TRUE"
nvme0:0.present = "TRUE"
nvme0:0.fileName = "$VM_NAME.vmdk"
sata0:1.present = "TRUE"
sata0:1.fileName = "$VM_NAME-cloud-init.iso"
sata0:1.deviceType = "cdrom-image"
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.virtualDev = "e1000e"
ethernet0.wakeOnPcktRcv = "FALSE"
ethernet0.addressType = "generated"
usb.present = "TRUE"
ehci.present = "TRUE"
usb_xhci.present = "TRUE"
floppy0.present = "FALSE"
firmware = "efi"
tools.syncTime = "TRUE"
powerType.powerOff = "soft"
powerType.powerOn = "soft"
powerType.suspend = "soft"
powerType.reset = "soft"
EOF
}
# [END_LOCKED_VMX]

# Function to create a single VM
create_single_vm() {
    local vm_name=$1
    local memory=$2
    local cpus=$3
    
    echo -e "\n${YELLOW}Creating VM: $vm_name${NC}"
    
    # Setup VM directory
    local VM_DIR="$VM_CLUSTER_DIR/$vm_name.vmwarevm"
    local VMX_FILE="$VM_DIR/$vm_name.vmx"
    
    # Delete existing VM if it exists
    if vmrun -T fusion list | grep -q "${VMX_FILE}"; then
        echo "Stopping existing VM..."
        vmrun -T fusion stop "${VMX_FILE}" soft || true
        sleep 5
    fi
    
    if [ -d "$VM_DIR" ]; then
        echo "Deleting existing VM directory: $VM_DIR"
        rm -rf "$VM_DIR"
    fi
    
    # Create VM directory
    echo "Creating VM directory: $VM_DIR"
    mkdir -p "$VM_DIR"
    
    # Load password
    PASSWORD=$(cat "$PASSWORD_FILE")
    
    # Create VM components
    create_vm_disk "$VM_DIR" "$vm_name"
    create_cloud_init_iso "$VM_DIR" "$vm_name" "$PASSWORD"
    create_vmx_file "$VM_DIR" "$vm_name" "$memory" "$cpus"
    
    # Start the VM
    echo -e "${YELLOW}Starting VM...${NC}"
    vmrun -T fusion start "$VMX_FILE"
    
    echo -e "${GREEN}VM $vm_name created successfully!${NC}"
    echo -e "${YELLOW}Waiting for VM to boot and get an IP address...${NC}"
    
    # Wait for VM to boot and get IP address
    VM_IP=$(vmrun -T fusion getGuestIPAddress "$VMX_FILE" -wait)
    echo -e "${GREEN}VM $vm_name IP address: $VM_IP${NC}"
    
    # Wait for SSH to be available
    echo -e "${YELLOW}Waiting for SSH on $vm_name to be available...${NC}"
    while ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$VM_IP "echo SSH connection successful" &>/dev/null; do
        echo -e "${YELLOW}Waiting for SSH on $vm_name...${NC}"
        sleep 5
    done
    echo -e "${GREEN}SSH connection to $vm_name successful${NC}"
    
    # Install basic packages
    echo -e "${YELLOW}Installing basic packages on $vm_name...${NC}"
    ssh -o StrictHostKeyChecking=no ubuntu@$VM_IP "sudo apt-get update && sudo apt-get install -y neovim tmux bash-completion curl wget htop net-tools"
    
    echo "$VM_IP"
}

# [LOCKED_FUNCTION: Do not modify the VM creation process]
# Function to create all VMs
create_vms() {
    print_header "Creating VMs"
    
    # Create VM cluster directory
    mkdir -p "$VM_CLUSTER_DIR"
    
    # Change to project directory
    cd "$PROJECT_DIR"
    
    # Create directory for VM IPs
    mkdir -p generated
    
    # Create empty vm-ips.env file first
    rm -f vm-ips.env
    touch vm-ips.env
    
    # Create HAProxy VMs
    echo -e "${YELLOW}Creating HAProxy VMs...${NC}"
    haproxy1_ip=$(create_single_vm "haproxy1" 2048 2)
    echo "haproxy1_ip = \"$haproxy1_ip\"" >> vm-ips.env
    
    haproxy2_ip=$(create_single_vm "haproxy2" 2048 2)
    echo "haproxy2_ip = \"$haproxy2_ip\"" >> vm-ips.env
    
    # Create Kubernetes master nodes
    echo -e "${YELLOW}Creating Kubernetes master nodes...${NC}"
    master1_ip=$(create_single_vm "k8s-master1" 4096 4)
    echo "master1_ip = \"$master1_ip\"" >> vm-ips.env
    
    master2_ip=$(create_single_vm "k8s-master2" 4096 4)
    echo "master2_ip = \"$master2_ip\"" >> vm-ips.env
    
    master3_ip=$(create_single_vm "k8s-master3" 4096 4)
    echo "master3_ip = \"$master3_ip\"" >> vm-ips.env
    
    # Create Kubernetes worker nodes
    echo -e "${YELLOW}Creating Kubernetes worker nodes...${NC}"
    worker1_ip=$(create_single_vm "k8s-worker1" 4096 4)
    echo "worker1_ip = \"$worker1_ip\"" >> vm-ips.env
    
    worker2_ip=$(create_single_vm "k8s-worker2" 4096 4)
    echo "worker2_ip = \"$worker2_ip\"" >> vm-ips.env
    
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
    echo -e "${GREEN}VM IPs saved to vm-ips.env${NC}"
    echo -e "\n${YELLOW}VM IPs:${NC}"
    cat vm-ips.env | sed 's/ = /: /g'
}
# [END_LOCKED_FUNCTION]

# Menu-driven functions will be added in subsequent edits

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

# Create all VMs and basic configuration
create_all_vms() {
    print_header "Creating all VMs and basic configuration"
    
    # Check if VMs already exist
    if [ -d "$VM_CLUSTER_DIR" ] && [ "$(find "$VM_CLUSTER_DIR" -name "*.vmwarevm" -type d | wc -l)" -gt 0 ]; then
        echo -e "${YELLOW}VMs already exist in $VM_CLUSTER_DIR${NC}"
        echo -e "${YELLOW}Do you want to delete existing VMs and create new ones? (y/n)${NC}"
        read -p "" -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}VM creation cancelled.${NC}"
            return
        fi
        
        # Remove existing VMs
        remove_existing_vms
    fi
    
    # Check for base image
    if [ ! -f "$BASE_IMAGE" ]; then
        echo -e "${YELLOW}Base image not found. Running download_base_image function...${NC}"
        download_base_image
    fi
    
    # Create VMs
    create_vms
    
    # Check if vm-ips.env was created
    if [ ! -f "vm-ips.env" ]; then
        echo -e "${RED}Error: vm-ips.env not created. VM creation may have failed.${NC}"
        return
    fi
    
    echo -e "${GREEN}VMs created successfully.${NC}"
    
    # Display VM information
    echo -e "\n${YELLOW}VM IP Addresses:${NC}"
    cat vm-ips.env | sed 's/ = /: /g'
}

# Check VM status and network configuration
check_vms() {
    print_header "Checking VM status and network configuration"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        echo -e "${YELLOW}Please create VMs first.${NC}"
        return
    fi
    
    # Check vm-ips.env
    if [ ! -f "vm-ips.env" ]; then
        echo -e "${RED}Error: vm-ips.env not found. VM information is missing.${NC}"
        echo -e "${YELLOW}This file is required for Terraform configuration.${NC}"
        return
    fi
    
    echo -e "${YELLOW}VM IP Addresses from vm-ips.env:${NC}"
    cat vm-ips.env | sed 's/ = /: /g'
    
    # Get list of VMs
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -name "*.vmwarevm" -type d)
    
    if [ -z "$VMWARE_VM_DIRS" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    echo -e "\n${YELLOW}Checking VM status and network configuration:${NC}"
    
    # Check each VM
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VMX_FILE="$VM_DIR/$VM_NAME.vmx"
        
        echo -e "\n${YELLOW}VM: $VM_NAME${NC}"
        
        if [ ! -f "$VMX_FILE" ]; then
            echo -e "${RED}Error: VMX file not found for $VM_NAME${NC}"
            continue
        fi
        
        # Check if VM is running and get IP address if it is
        if vmrun -T fusion list | grep -q "$VMX_FILE"; then
            VM_IP=$(vmrun -T fusion getGuestIPAddress "$VMX_FILE" 2>/dev/null || echo "Unknown")
            echo -e "${GREEN}Status: Running${NC}"
            echo -e "${GREEN}IP address: $VM_IP${NC}"
            
            # Compare with vm-ips.env
            VM_ENV_IP=$(grep "${VM_NAME/_/-}_ip" vm-ips.env 2>/dev/null | cut -d '"' -f 2 || echo "Not found in vm-ips.env")
            
            if [ "$VM_ENV_IP" != "$VM_IP" ] && [ "$VM_ENV_IP" != "Not found in vm-ips.env" ]; then
                echo -e "${RED}Warning: IP address mismatch!${NC}"
                echo -e "${RED}Current IP: $VM_IP${NC}"
                echo -e "${RED}IP in vm-ips.env: $VM_ENV_IP${NC}"
            fi
            
            # Try to check network interface in VM
            if [ "$VM_IP" != "Unknown" ]; then
                echo -e "${YELLOW}Checking network interfaces in VM...${NC}"
                ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$VM_IP "ip addr show | grep -E 'inet.*global'" 2>/dev/null || echo -e "${RED}Could not connect to VM to check network interfaces${NC}"
            fi
        else
            echo -e "${RED}Status: Not running${NC}"
        fi
    done
    
    # Validate vm-ips.env against running VMs
    print_header "Validating vm-ips.env file"
    echo -e "${YELLOW}Checking if all VM IPs in vm-ips.env are reachable...${NC}"
    
    source vm-ips.env
    IPS_ARRAY=(${haproxy1_ip} ${haproxy2_ip} ${master1_ip} ${master2_ip} ${master3_ip} ${worker1_ip} ${worker2_ip})
    NAMES_ARRAY=("HAProxy1" "HAProxy2" "Master1" "Master2" "Master3" "Worker1" "Worker2")
    
    for i in "${!IPS_ARRAY[@]}"; do
        IP=${IPS_ARRAY[$i]}
        NAME=${NAMES_ARRAY[$i]}
        
        echo -e "${YELLOW}Checking $NAME ($IP)...${NC}"
        if ping -c 1 -W 2 "$IP" &>/dev/null; then
            echo -e "${GREEN}$NAME is reachable.${NC}"
        else
            echo -e "${RED}Warning: $NAME is not reachable. This may cause issues with deployment.${NC}"
        fi
    done
}

# Create snapshots of all VMs
create_snapshots() {
    print_header "Creating snapshots of all VMs"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        echo -e "${YELLOW}Please create VMs first.${NC}"
        return
    fi
    
    # Get list of VMs
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -name "*.vmwarevm" -type d)
    
    if [ -z "$VMWARE_VM_DIRS" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    # Prompt for snapshot name
    echo -e "${YELLOW}Enter a name for the snapshot:${NC}"
    read SNAPSHOT_NAME
    
    if [ -z "$SNAPSHOT_NAME" ]; then
        echo -e "${RED}Error: Snapshot name cannot be empty.${NC}"
        return
    fi
    
    # Create snapshot for each VM
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VMX_FILE="$VM_DIR/$VM_NAME.vmx"
        
        echo -e "${YELLOW}Creating snapshot for $VM_NAME...${NC}"
        
        if [ ! -f "$VMX_FILE" ]; then
            echo -e "${RED}Error: VMX file not found for $VM_NAME${NC}"
            continue
        fi
        
        # Create snapshot
        vmrun -T fusion snapshot "$VMX_FILE" "$SNAPSHOT_NAME" || echo -e "${RED}Failed to create snapshot for $VM_NAME${NC}"
    done
    
    echo -e "${GREEN}Snapshots created successfully.${NC}"
}

# List snapshots for all VMs
list_snapshots() {
    print_header "Listing snapshots for all VMs"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        echo -e "${YELLOW}Please create VMs first.${NC}"
        return
    fi
    
    # Get list of VMs
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -name "*.vmwarevm" -type d)
    
    if [ -z "$VMWARE_VM_DIRS" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    # List snapshots for each VM
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VMX_FILE="$VM_DIR/$VM_NAME.vmx"
        
        echo -e "\n${YELLOW}Snapshots for $VM_NAME:${NC}"
        
        if [ ! -f "$VMX_FILE" ]; then
            echo -e "${RED}Error: VMX file not found for $VM_NAME${NC}"
            continue
        fi
        
        # List snapshots
        SNAPSHOTS=$(vmrun -T fusion listSnapshots "$VMX_FILE" 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error listing snapshots for $VM_NAME${NC}"
        elif [ -z "$SNAPSHOTS" ] || echo "$SNAPSHOTS" | grep -q "No snapshots"; then
            echo -e "${YELLOW}No snapshots found for $VM_NAME${NC}"
        else
            echo "$SNAPSHOTS" | grep -v "Total snapshots"
        fi
    done
}

# Rollback to a snapshot
rollback_to_snapshot() {
    print_header "Rollback to snapshot"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        echo -e "${YELLOW}Please create VMs first.${NC}"
        return
    fi
    
    # Get list of VMs
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -name "*.vmwarevm" -type d)
    
    if [ -z "$VMWARE_VM_DIRS" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    # Select a VM for snapshot listing
    echo -e "${YELLOW}Available VMs:${NC}"
    VM_ARRAY=()
    i=1
    
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VM_ARRAY+=("$VM_DIR")
        echo -e "$i) $VM_NAME"
        i=$((i+1))
    done
    
    echo -e "${YELLOW}Select a VM to view snapshots (1-$((i-1))):${NC}"
    read VM_SELECTION
    
    if ! [[ "$VM_SELECTION" =~ ^[0-9]+$ ]] || [ "$VM_SELECTION" -lt 1 ] || [ "$VM_SELECTION" -gt $((i-1)) ]; then
        echo -e "${RED}Invalid selection.${NC}"
        return
    fi
    
    VM_DIR=${VM_ARRAY[$((VM_SELECTION-1))]}
    VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
    VMX_FILE="$VM_DIR/$VM_NAME.vmx"
    
    # List snapshots for the selected VM
    echo -e "\n${YELLOW}Snapshots for $VM_NAME:${NC}"
    SNAPSHOTS=$(vmrun -T fusion listSnapshots "$VMX_FILE" 2>/dev/null | grep -v "Total snapshots")
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error listing snapshots for $VM_NAME${NC}"
        return
    elif [ -z "$SNAPSHOTS" ]; then
        echo -e "${YELLOW}No snapshots found for $VM_NAME${NC}"
        return
    fi
    
    # Create an array of snapshot names
    SNAPSHOT_ARRAY=()
    i=1
    
    while IFS= read -r SNAPSHOT; do
        SNAPSHOT_ARRAY+=("$SNAPSHOT")
        echo -e "$i) $SNAPSHOT"
        i=$((i+1))
    done <<< "$SNAPSHOTS"
    
    # Select a snapshot
    echo -e "${YELLOW}Select a snapshot to rollback to (1-$((i-1))):${NC}"
    read SNAPSHOT_SELECTION
    
    if ! [[ "$SNAPSHOT_SELECTION" =~ ^[0-9]+$ ]] || [ "$SNAPSHOT_SELECTION" -lt 1 ] || [ "$SNAPSHOT_SELECTION" -gt $((i-1)) ]; then
        echo -e "${RED}Invalid selection.${NC}"
        return
    fi
    
    SELECTED_SNAPSHOT=${SNAPSHOT_ARRAY[$((SNAPSHOT_SELECTION-1))]}
    
    # Confirm rollback
    echo -e "${RED}Warning: This will revert the VM to the selected snapshot state. All changes since then will be lost.${NC}"
    echo -e "${YELLOW}Are you sure you want to rollback $VM_NAME to snapshot '$SELECTED_SNAPSHOT'? (y/n)${NC}"
    read -p "" -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Rollback cancelled.${NC}"
        return
    fi
    
    # Stop VM if running
    if vmrun -T fusion list | grep -q "$VMX_FILE"; then
        echo -e "${YELLOW}Stopping VM...${NC}"
        vmrun -T fusion stop "$VMX_FILE" soft || true
        sleep 5
    fi
    
    # Rollback to snapshot
    echo -e "${YELLOW}Rolling back to snapshot...${NC}"
    vmrun -T fusion revertToSnapshot "$VMX_FILE" "$SELECTED_SNAPSHOT"
    
    # Start VM
    echo -e "${YELLOW}Starting VM...${NC}"
    vmrun -T fusion start "$VMX_FILE"
    
    echo -e "${GREEN}VM $VM_NAME has been rolled back to snapshot '$SELECTED_SNAPSHOT'.${NC}"
}

# Delete all snapshots
delete_all_snapshots() {
    print_header "Deleting all snapshots"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        echo -e "${YELLOW}Please create VMs first.${NC}"
        return
    fi
    
    # Get list of VMs
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -name "*.vmwarevm" -type d)
    
    if [ -z "$VMWARE_VM_DIRS" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    # Confirm deletion
    echo -e "${RED}Warning: This will delete ALL snapshots for ALL VMs.${NC}"
    echo -e "${YELLOW}Are you sure you want to continue? (y/n)${NC}"
    read -p "" -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Deletion cancelled.${NC}"
        return
    fi
    
    # Delete snapshots for each VM
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VMX_FILE="$VM_DIR/$VM_NAME.vmx"
        
        echo -e "${YELLOW}Deleting snapshots for $VM_NAME...${NC}"
        
        if [ ! -f "$VMX_FILE" ]; then
            echo -e "${RED}Error: VMX file not found for $VM_NAME${NC}"
            continue
        fi
        
        # List snapshots
        SNAPSHOTS=$(vmrun -T fusion listSnapshots "$VMX_FILE" 2>/dev/null | grep -v "Total snapshots")
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error listing snapshots for $VM_NAME${NC}"
        elif [ -z "$SNAPSHOTS" ]; then
            echo -e "${YELLOW}No snapshots found for $VM_NAME${NC}"
        else
            # Delete each snapshot
            while IFS= read -r SNAPSHOT; do
                echo -e "${YELLOW}Deleting snapshot '$SNAPSHOT' for $VM_NAME...${NC}"
                vmrun -T fusion deleteSnapshot "$VMX_FILE" "$SNAPSHOT" || echo -e "${RED}Failed to delete snapshot '$SNAPSHOT' for $VM_NAME${NC}"
            done <<< "$SNAPSHOTS"
        fi
    done
    
    echo -e "${GREEN}All snapshots have been deleted.${NC}"
}

# Deploy Kubernetes workflow
deploy_k8s_workflow() {
    print_header "Deploying Kubernetes Cluster Workflow"
    
    # Check prerequisites
    check_prerequisites
    
    # Ask for confirmation
    echo -e "${YELLOW}This workflow will:${NC}"
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
        return
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
        echo -e "${YELLOW}Kubernetes deployment skipped. You can deploy it later by running this script.${NC}"
        return
    fi
    
    # Deploy Kubernetes
    deploy_kubernetes
    
    # Display cluster information
    display_cluster_info
}

# Main menu
display_menu() {
    print_header "Kubernetes Cluster Management Menu"
    echo -e "1) Deploy Kubernetes Cluster (Full Workflow)"
    echo -e "2) Create all VMs and basic configuration"
    echo -e "3) Check VM status and network configuration"
    echo -e "4) Create snapshots of all VMs"
    echo -e "5) List snapshots for all VMs"
    echo -e "6) Rollback to a snapshot"
    echo -e "7) Delete all snapshots"
    echo -e "8) Delete all VMs"
    echo -e "9) Deploy Kubernetes on existing VMs"
    echo -e "0) Exit"
    echo -e "\n${YELLOW}Enter your choice:${NC}"
}

# Main function
main() {
    # Check prerequisites silently
    check_prerequisites > /dev/null 2>&1 || true
    
    while true; do
        display_menu
        read -p "" CHOICE
        
        case $CHOICE in
            1)
                deploy_k8s_workflow
                ;;
            2)
                create_all_vms
                ;;
            3)
                check_vms
                ;;
            4)
                create_snapshots
                ;;
            5)
                list_snapshots
                ;;
            6)
                rollback_to_snapshot
                ;;
            7)
                delete_all_snapshots
                ;;
            8)
                remove_existing_vms
                ;;
            9)
                if [ ! -f "vm-ips.env" ]; then
                    echo -e "${RED}Error: vm-ips.env not found. Please create VMs first.${NC}"
                else
                    setup_terraform && deploy_kubernetes && display_cluster_info
                fi
                ;;
            0)
                echo -e "${GREEN}Exiting...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                ;;
        esac
        
        echo -e "\n${YELLOW}Press Enter to continue...${NC}"
        read
    done
}

# Run main function
main 