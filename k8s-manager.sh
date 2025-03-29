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
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# [LOCKED_CONFIG: Do not modify these critical settings]
# Configuration
BASE_IMAGE_PATH="$HOME/godz/k8s/base_images/noble-server-cloudimg-arm64.img"
BASE_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img"
VM_CLUSTER_DIR="/Users/alf/VMs/k8s_cluster"
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
        echo -e "${CYAN}You may need to add the following to your .zshrc or .bashrc:${NC}"
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
        echo -e "${CYAN}Please create an SSH key pair using:${NC}"
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
        echo -e "${CYAN}Password file not found. Creating a secure password...${NC}"
        # Generate a random password and save it to the file
        openssl rand -base64 12 > "$PASSWORD_FILE"
        chmod 600 "$PASSWORD_FILE"
        echo -e "${GREEN}Password file created at $PASSWORD_FILE${NC}"
    else
        chmod 600 "$PASSWORD_FILE"
    fi
    
    # Check if documentation exists
    if [ ! -f "./docs/vm_deployment.md" ]; then
        echo -e "${CYAN}Warning: Documentation file not found at ./docs/vm_deployment.md${NC}"
        echo -e "${CYAN}It is recommended to read the documentation before proceeding.${NC}"
    else
        echo -e "${GREEN}Found VM deployment documentation at ./docs/vm_deployment.md${NC}"
        echo -e "${CYAN}Please review this document for important information about the VM deployment process.${NC}"
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
        echo -e "${CYAN}Found running VMs:${NC}"
        echo "$RUNNING_VMS"
        
        # Stop each running VM
        echo -e "${CYAN}Stopping running VMs...${NC}"
        echo "$RUNNING_VMS" | while read -r VM_PATH; do
            if [ -n "$VM_PATH" ]; then
                VM_NAME=$(basename "$(dirname "$VM_PATH")" | sed 's/\.vmwarevm//')
                echo -e "${CYAN}Stopping VM: $VM_NAME${NC}"
                vmrun -T fusion stop "$VM_PATH" soft || true
                sleep 2
            fi
        done
    else
        echo -e "${GREEN}No running VMs found.${NC}"
    fi
    
    # Remove VM directory if it exists
    if [ -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${CYAN}Removing VM directory: $VM_CLUSTER_DIR${NC}"
        rm -rf "$VM_CLUSTER_DIR"
    else
        echo -e "${GREEN}VM directory does not exist: $VM_CLUSTER_DIR${NC}"
    fi
    
    # Clean up VM-related files
    echo -e "${CYAN}Cleaning up VM-related files...${NC}"
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
        echo -e "${CYAN}Base image not found. Downloading...${NC}"
        echo -e "${CYAN}Downloading Ubuntu 24.04 LTS ARM64 cloud image...${NC}"
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
    
    echo -e "${CYAN}Creating VM disk from base image...${NC}"
    # First convert to qcow2 format (better handling of conversion)
    TEMP_QCOW2="$VM_DIR/temp_disk.qcow2"
    echo -e "${CYAN}Converting raw image to qcow2 format...${NC}"
    qemu-img convert -f raw -O qcow2 "$BASE_IMAGE" "$TEMP_QCOW2"

    # Resize the qcow2 image
    echo -e "${CYAN}Resizing disk image to $VM_DISK_SIZE...${NC}"
    qemu-img resize "$TEMP_QCOW2" $VM_DISK_SIZE

    # Convert qcow2 to vmdk for VMware
    echo -e "${CYAN}Converting to vmdk format...${NC}"
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
    
    echo -e "${CYAN}Creating cloud-init configuration...${NC}"

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
    echo -e "${CYAN}Creating cloud-init ISO...${NC}"
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
    
    echo -e "${CYAN}Creating VMX file...${NC}"
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

# Function to update VM IPs file
update_vm_ips() {
    print_header "Updating VM IP addresses"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        echo -e "${CYAN}Please create VMs first.${NC}"
        return
    fi
    
    # Get list of VM directories
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -maxdepth 1 -name "*.vmwarevm" -type d)
    
    if [ -z "$VMWARE_VM_DIRS" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    # Create empty vm-ips.env file
    echo -e "${CYAN}Creating new vm-ips.env file...${NC}"
    rm -f vm-ips.env
    touch vm-ips.env
    
    # Get IP for each VM
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VMX_FILE="$VM_DIR/$VM_NAME.vmx"
        
        echo -e "${CYAN}Getting IP for VM: $VM_NAME${NC}"
        
        if [ ! -f "$VMX_FILE" ]; then
            echo -e "${RED}Error: VMX file not found for $VM_NAME${NC}"
            continue
        fi
        
        # Check if VM is running
        if vmrun -T fusion list | grep -q "$VMX_FILE"; then
            VM_IP=$(vmrun -T fusion getGuestIPAddress "$VMX_FILE" 2>/dev/null || echo "")
            
            # Validate that we got a valid IP address (basic check)
            if [[ $VM_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo -e "${GREEN}VM $VM_NAME IP address: $VM_IP${NC}"
                
                # Format name for vm-ips.env
                ENV_NAME=$(echo "$VM_NAME" | sed 's/k8s-//g')_ip
                
                # Add IP to vm-ips.env
                echo "$ENV_NAME = \"$VM_IP\"" >> vm-ips.env
            else
                echo -e "${RED}Invalid or empty IP address for VM $VM_NAME: '$VM_IP'${NC}"
            fi
        else
            echo -e "${RED}VM $VM_NAME is not running. Starting VM...${NC}"
            vmrun -T fusion start "$VMX_FILE"
            
            # Wait for VM to boot and get IP
            echo -e "${CYAN}Waiting for VM to boot and get an IP address...${NC}"
            
            # Try multiple times to get the IP
            VM_IP=""
            local GET_IP_SUCCESS=false
            
            for i in {1..10}; do
                sleep 10
                VM_IP=$(vmrun -T fusion getGuestIPAddress "$VMX_FILE" 2>/dev/null || echo "")
                
                # Validate that we got a valid IP address (basic check)
                if [[ $VM_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    echo -e "${GREEN}VM $VM_NAME IP address: $VM_IP${NC}"
                    
                    # Format name for vm-ips.env
                    ENV_NAME=$(echo "$VM_NAME" | sed 's/k8s-//g')_ip
                    
                    # Add IP to vm-ips.env
                    echo "$ENV_NAME = \"$VM_IP\"" >> vm-ips.env
                    GET_IP_SUCCESS=true
                    break
                fi
                
                echo -e "${CYAN}Waiting for IP ($i/10)...${NC}"
            done
            
            if [ "$GET_IP_SUCCESS" = false ]; then
                echo -e "${RED}Could not get a valid IP address for VM $VM_NAME after multiple attempts${NC}"
            fi
        fi
    done
    
    # Check if all required VMs have entries
    local MISSING_VMS=false
    local REQUIRED_VMS=("haproxy1" "haproxy2" "k8s-master1" "k8s-master2" "k8s-master3" "k8s-worker1" "k8s-worker2")
    
    for VM in "${REQUIRED_VMS[@]}"; do
        ENV_NAME=$(echo "$VM" | sed 's/k8s-//g')_ip
        if ! grep -q "$ENV_NAME" vm-ips.env; then
            echo -e "${RED}Missing IP address for VM $VM in vm-ips.env${NC}"
            MISSING_VMS=true
        fi
    done
    
    if [ "$MISSING_VMS" = true ]; then
        echo -e "${RED}Some VMs are missing from vm-ips.env. This may cause issues with Terraform deployment.${NC}"
    fi
    
    # Display IP addresses
    echo -e "\n${GREEN}Updated VM IP addresses:${NC}"
    cat vm-ips.env
    
    echo -e "\n${GREEN}VM IPs have been updated successfully.${NC}"
}

# Function to create a single VM
create_single_vm() {
    local vm_name=$1
    local memory=$2
    local cpus=$3
    
    echo -e "\n${CYAN}Creating VM: $vm_name${NC}"
    
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
    echo -e "${CYAN}Starting VM...${NC}"
    vmrun -T fusion start "$VMX_FILE"
    
    echo -e "${GREEN}VM $vm_name created successfully!${NC}"
    echo -e "${CYAN}Waiting for VM to boot and get an IP address...${NC}"
    
    # Wait for VM to boot and get IP address
    local VM_IP=""
    local MAX_ATTEMPTS=20
    local ATTEMPT=0
    
    while [ "$VM_IP" = "" ] && [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        VM_IP=$(vmrun -T fusion getGuestIPAddress "$VMX_FILE" -wait 2>/dev/null || echo "")
        if [ -z "$VM_IP" ]; then
            ATTEMPT=$((ATTEMPT+1))
            echo -e "${CYAN}Waiting for IP address ($ATTEMPT/$MAX_ATTEMPTS)...${NC}"
            sleep 10
        fi
    done
    
    if [ -n "$VM_IP" ]; then
        echo -e "${GREEN}VM $vm_name IP address: $VM_IP${NC}"
    else
        echo -e "${RED}Failed to get IP address for $vm_name after $MAX_ATTEMPTS attempts${NC}"
        echo -e "${RED}Deployment may not function correctly.${NC}"
        return
    fi
    
    # Wait for SSH to be available
    echo -e "${CYAN}Waiting for SSH on $vm_name to be available...${NC}"
    local SSH_AVAILABLE=false
    local SSH_ATTEMPTS=0
    local MAX_SSH_ATTEMPTS=12
    
    while [ "$SSH_AVAILABLE" = false ] && [ $SSH_ATTEMPTS -lt $MAX_SSH_ATTEMPTS ]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$VM_IP "echo SSH connection successful" &>/dev/null; then
            SSH_AVAILABLE=true
            echo -e "${GREEN}SSH connection to $vm_name successful${NC}"
        else
            SSH_ATTEMPTS=$((SSH_ATTEMPTS+1))
            echo -e "${CYAN}Waiting for SSH on $vm_name ($SSH_ATTEMPTS/$MAX_SSH_ATTEMPTS)...${NC}"
            sleep 10
        fi
    done
    
    if [ "$SSH_AVAILABLE" = false ]; then
        echo -e "${RED}Failed to establish SSH connection to $vm_name after $MAX_SSH_ATTEMPTS attempts${NC}"
        echo -e "${RED}Deployment may not function correctly.${NC}"
        return
    fi
    
    # Install basic packages
    echo -e "${CYAN}Installing basic packages on $vm_name...${NC}"
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
    echo -e "${CYAN}Creating HAProxy VMs...${NC}"
    haproxy1_ip=$(create_single_vm "haproxy1" 2048 2)
    echo "haproxy1_ip = \"$haproxy1_ip\"" >> vm-ips.env
    
    haproxy2_ip=$(create_single_vm "haproxy2" 2048 2)
    echo "haproxy2_ip = \"$haproxy2_ip\"" >> vm-ips.env
    
    # Create Kubernetes master nodes
    echo -e "${CYAN}Creating Kubernetes master nodes...${NC}"
    master1_ip=$(create_single_vm "k8s-master1" 4096 4)
    echo "master1_ip = \"$master1_ip\"" >> vm-ips.env
    
    master2_ip=$(create_single_vm "k8s-master2" 4096 4)
    echo "master2_ip = \"$master2_ip\"" >> vm-ips.env
    
    master3_ip=$(create_single_vm "k8s-master3" 4096 4)
    echo "master3_ip = \"$master3_ip\"" >> vm-ips.env
    
    # Create Kubernetes worker nodes
    echo -e "${CYAN}Creating Kubernetes worker nodes...${NC}"
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
    echo -e "\n${CYAN}VM IPs:${NC}"
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
    echo -e "${CYAN}Running terraform-setup.sh to set up Terraform...${NC}"
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
    echo -e "${CYAN}Running terraform plan to check for errors...${NC}"
    terraform plan
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: terraform plan failed. Please check the errors above.${NC}"
        exit 1
    fi
    
    # Run terraform apply
    echo -e "${CYAN}Running terraform apply to deploy Kubernetes...${NC}"
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
    echo -e "\n${CYAN}Cluster Information:${NC}"
    echo -e "Virtual IP (HAProxy): 10.10.0.100"
    echo -e "HAProxy Stats: http://10.10.0.100:9000 (admin:admin)"
    echo -e "Master Node 1: $MASTER1_IP"
    echo -e "\n${CYAN}To access the cluster:${NC}"
    echo -e "ssh ubuntu@$MASTER1_IP"
    echo -e "\n${CYAN}To check cluster status:${NC}"
    echo -e "kubectl get nodes -o wide"
    echo -e "kubectl get pods -A"
    
    # Display password information
    echo -e "\n${CYAN}VM Password Information:${NC}"
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
        echo -e "${CYAN}Checking connectivity to $vm_name ($vm_ip)...${NC}"
        
        if ping -c 1 -W 2 "$vm_ip" &>/dev/null; then
            echo -e "${GREEN}$vm_name is reachable.${NC}"
        else
            echo -e "${RED}Warning: $vm_name is not reachable. This may cause issues with deployment.${NC}"
            echo -e "${CYAN}Do you want to continue anyway? (y/n)${NC}"
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
        echo -e "${CYAN}VMs already exist in $VM_CLUSTER_DIR${NC}"
        echo -e "${CYAN}Do you want to delete existing VMs and create new ones? (y/n)${NC}"
        read -p "" -n 1 -r
        echo
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}VM creation cancelled.${NC}"
            return
        fi
        
        # Remove existing VMs
        remove_existing_vms
    fi
    
    # Check for base image
    if [ ! -f "$BASE_IMAGE" ]; then
        echo -e "${CYAN}Base image not found. Running download_base_image function...${NC}"
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
    echo -e "\n${CYAN}VM IP Addresses:${NC}"
    cat vm-ips.env | sed 's/ = /: /g'
}

# Function to power on all VMs
power_on_all_vms() {
    print_header "Powering on all VMs"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        echo -e "${CYAN}Please create VMs first.${NC}"
        return
    fi
    
    echo -e "${CYAN}VM cluster directory: $VM_CLUSTER_DIR${NC}"
    
    # Get list of VMs - properly quoted to handle spaces in path
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -maxdepth 1 -name "*.vmwarevm" -type d)
    
    if [ -z "$VMWARE_VM_DIRS" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        # List what actually exists in the directory
        echo -e "${CYAN}Contents of VM directory:${NC}"
        ls -la "$VM_CLUSTER_DIR"
        return
    fi
    
    echo -e "${CYAN}Starting all VMs...${NC}"
    
    # Start each VM
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VMX_FILE="$VM_DIR/$VM_NAME.vmx"
        
        echo -e "${CYAN}Starting VM: $VM_NAME${NC}"
        echo -e "${CYAN}VM path: $VM_DIR${NC}"
        echo -e "${CYAN}VMX file: $VMX_FILE${NC}"
        
        if [ ! -f "$VMX_FILE" ]; then
            echo -e "${RED}Error: VMX file not found for $VM_NAME${NC}"
            continue
        fi
        
        # Check if VM is already running
        if vmrun -T fusion list | grep -q "$VMX_FILE"; then
            echo -e "${GREEN}VM $VM_NAME is already running.${NC}"
        else
            echo -e "${CYAN}Starting VM $VM_NAME...${NC}"
            vmrun -T fusion start "$VMX_FILE" || echo -e "${RED}Failed to start VM $VM_NAME${NC}"
        fi
    done
    
    echo -e "${GREEN}All VMs have been powered on.${NC}"
}

# Function to shutdown all VMs
shutdown_all_vms() {
    print_header "Shutting down all VMs"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        echo -e "${CYAN}Please create VMs first.${NC}"
        return
    fi
    
    echo -e "${CYAN}VM cluster directory: $VM_CLUSTER_DIR${NC}"
    
    # Get list of running VMs - using exact path
    RUNNING_VMS=$(vmrun -T fusion list | grep -v "Total running VMs" | grep "$VM_CLUSTER_DIR" || true)
    
    if [ -z "$RUNNING_VMS" ]; then
        echo -e "${GREEN}No running VMs found. All VMs are already powered off.${NC}"
        return
    fi
    
    echo -e "${CYAN}Found running VMs:${NC}"
    echo "$RUNNING_VMS"
    
    # Confirm shutdown
    echo -e "${CYAN}Are you sure you want to shutdown all VMs? (y/n)${NC}"
    read -p "" -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Shutdown cancelled.${NC}"
        return
    fi
    
    # Shutdown each running VM
    echo -e "${CYAN}Shutting down running VMs...${NC}"
    echo "$RUNNING_VMS" | while read -r VM_PATH; do
        if [ -n "$VM_PATH" ]; then
            VM_NAME=$(basename "$(dirname "$VM_PATH")" | sed 's/\.vmwarevm//')
            echo -e "${CYAN}Shutting down VM: $VM_NAME${NC}"
            echo -e "${CYAN}VM path: $VM_PATH${NC}"
            # Use the "soft" option for proper graceful shutdown per VMware Fusion documentation
            vmrun -T fusion stop "$VM_PATH" soft || echo -e "${RED}Failed to shutdown VM $VM_NAME${NC}"
            sleep 5
        fi
    done
    
    # Verify all VMs are stopped
    RUNNING_VMS_AFTER=$(vmrun -T fusion list | grep -v "Total running VMs" | grep "$VM_CLUSTER_DIR" || true)
    
    if [ -n "$RUNNING_VMS_AFTER" ]; then
        echo -e "${RED}Some VMs are still running:${NC}"
        echo "$RUNNING_VMS_AFTER"
        echo -e "${CYAN}Do you want to force power off these VMs? (y/n)${NC}"
        read -p "" -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}Force powering off remaining VMs...${NC}"
            echo "$RUNNING_VMS_AFTER" | while read -r VM_PATH; do
                if [ -n "$VM_PATH" ]; then
                    VM_NAME=$(basename "$(dirname "$VM_PATH")" | sed 's/\.vmwarevm//')
                    echo -e "${CYAN}Force powering off VM: $VM_NAME${NC}"
                    # Use "hard" option for force power off as described in VMware Fusion documentation
                    vmrun -T fusion stop "$VM_PATH" hard || echo -e "${RED}Failed to force power off VM $VM_NAME${NC}"
                    sleep 5
                fi
            done
        fi
    fi
    
    echo -e "${GREEN}All VMs have been shut down.${NC}"
}

# Check VM status and network configuration
check_vms() {
    print_header "Checking VM status and network configuration"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        echo -e "${CYAN}Please create VMs first.${NC}"
        return
    fi
    
    echo -e "${CYAN}VM cluster directory: $VM_CLUSTER_DIR${NC}"
    
    # Check vm-ips.env
    if [ ! -f "vm-ips.env" ]; then
        echo -e "${RED}Error: vm-ips.env not found. VM information is missing.${NC}"
        echo -e "${CYAN}This file is required for Terraform configuration.${NC}"
        return
    fi
    
    echo -e "${CYAN}VM IP Addresses from vm-ips.env:${NC}"
    cat vm-ips.env | sed 's/ = /: /g'
    
    # Get list of VMs - properly handle spaces in path
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -maxdepth 1 -name "*.vmwarevm" -type d)
    
    if [ -z "$VMWARE_VM_DIRS" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        # List what actually exists in the directory
        echo -e "${CYAN}Contents of VM directory:${NC}"
        ls -la "$VM_CLUSTER_DIR"
        return
    fi
    
    echo -e "\n${CYAN}Checking VM status and network configuration:${NC}"
    
    # Track powered off VMs
    POWERED_OFF_VMS=()
    
    # Check each VM
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VMX_FILE="$VM_DIR/$VM_NAME.vmx"
        
        # Get the env var name from VM name
        ENV_NAME=$(echo "$VM_NAME" | sed 's/k8s-//g')_ip
        
        echo -e "\n${CYAN}VM: $VM_NAME${NC}"
        echo -e "${CYAN}VM path: $VM_DIR${NC}"
        echo -e "${CYAN}VMX file: $VMX_FILE${NC}"
        
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
            VM_ENV_IP=$(grep "${ENV_NAME}" vm-ips.env 2>/dev/null | cut -d '"' -f 2 || echo "")
            
            if [ "$VM_ENV_IP" != "$VM_IP" ] && [ -n "$VM_ENV_IP" ]; then
                echo -e "${RED}Warning: IP address mismatch!${NC}"
                echo -e "${RED}Current IP: $VM_IP${NC}"
                echo -e "${RED}IP in vm-ips.env: $VM_ENV_IP${NC}"
            fi
            
            # Try to check network interface in VM
            if [ "$VM_IP" != "Unknown" ]; then
                echo -e "${CYAN}Checking network interfaces in VM...${NC}"
                ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$VM_IP "ip addr show | grep -E 'inet.*global'" 2>/dev/null || echo -e "${RED}Could not connect to VM to check network interfaces${NC}"
            fi
        else
            echo -e "${RED}Status: Not running${NC}"
            POWERED_OFF_VMS+=("$VM_NAME")
        fi
    done
    
    # Validate vm-ips.env against running VMs
    print_header "Validating vm-ips.env file"
    echo -e "${CYAN}Checking if all VM IPs in vm-ips.env are reachable...${NC}"
    
    if [ -f "vm-ips.env" ] && [ -s "vm-ips.env" ]; then
        # Process the vm-ips.env file line by line
        while IFS= read -r line; do
            # Skip empty lines
            [ -z "$line" ] && continue
            
            # Extract the VM name and IP
            if [[ "$line" =~ ([a-zA-Z0-9_]+)\ =\ \"([0-9.]+)\" ]]; then
                name="${BASH_REMATCH[1]}"
                ip="${BASH_REMATCH[2]}"
                
                # Extract the VM name by removing the _ip suffix
                vm_name=${name%_ip}
                
                # Make the display name nicer
                case "$vm_name" in
                    haproxy1) display_name="HAProxy1" ;;
                    haproxy2) display_name="HAProxy2" ;;
                    master1) display_name="Master1" ;;
                    master2) display_name="Master2" ;;
                    master3) display_name="Master3" ;;
                    worker1) display_name="Worker1" ;;
                    worker2) display_name="Worker2" ;;
                    *) display_name="$vm_name" ;;
                esac
                
                echo -e "${CYAN}Checking $display_name ($ip)...${NC}"
                if ping -c 1 -W 2 "$ip" &>/dev/null; then
                    echo -e "${GREEN}$display_name is reachable.${NC}"
                else
                    echo -e "${RED}Warning: $display_name is not reachable. This may cause issues with deployment.${NC}"
                fi
            fi
        done < vm-ips.env
    else
        echo -e "${RED}Error: vm-ips.env is empty or has an incorrect format.${NC}"
    fi
    
    # If there are powered off VMs, suggest starting them
    if [ ${#POWERED_OFF_VMS[@]} -gt 0 ]; then
        echo -e "\n${CYAN}Some VMs are powered off:${NC}"
        for VM in "${POWERED_OFF_VMS[@]}"; do
            echo -e "${CYAN}  - $VM${NC}"
        done
        
        echo -e "\n${CYAN}Would you like to power on these VMs now? (y/n)${NC}"
        read -p "" -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            power_on_all_vms
        else
            echo -e "${CYAN}You can power on all VMs later by selecting the 'Power on all VMs' option from the main menu.${NC}"
        fi
    fi
}

# Create snapshots of all VMs
create_snapshots() {
    print_header "Creating snapshots of all VMs"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        echo -e "${CYAN}Please create VMs first.${NC}"
        return
    fi
    
    # Get list of VMs
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -maxdepth 1 -name "*.vmwarevm" -type d)
    
    if [ -z "$VMWARE_VM_DIRS" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    # Prompt for snapshot name (don't allow forward slashes)
    echo -e "${CYAN}Enter a name for the snapshot (avoid using '/' characters):${NC}"
    read SNAPSHOT_NAME
    
    if [ -z "$SNAPSHOT_NAME" ]; then
        echo -e "${RED}Error: Snapshot name cannot be empty.${NC}"
        return
    fi
    
    # Check if snapshot name contains forward slashes
    if [[ "$SNAPSHOT_NAME" == */* ]]; then
        echo -e "${RED}Error: Snapshot name cannot contain '/' character as it's used for snapshot paths.${NC}"
        return
    fi
    
    # Use temporary file to track process IDs
    TEMP_PIDS_FILE=$(mktemp)
    
    # Create snapshots in parallel
    echo -e "${GREEN}Creating snapshots in parallel for faster processing...${NC}"
    
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VMX_FILE="$VM_DIR/$VM_NAME.vmx"
        
        if [ ! -f "$VMX_FILE" ]; then
            echo -e "${RED}Error: VMX file not found for $VM_NAME${NC}"
            continue
        fi
        
        # Create snapshot in background process
        (
            echo -e "${CYAN}Starting snapshot creation for $VM_NAME...${NC}"
            
            # Check if VM is running
            if vmrun -T fusion list | grep -q "$VMX_FILE"; then
                echo -e "${CYAN}VM $VM_NAME is running. Taking snapshot...${NC}"
            else
                echo -e "${CYAN}VM $VM_NAME is not running. Taking snapshot...${NC}"
            fi
            
            # Take snapshot using vmrun with minimal options
            if vmrun -T fusion snapshot "$VMX_FILE" "$SNAPSHOT_NAME"; then
                echo -e "${GREEN}Successfully created snapshot '$SNAPSHOT_NAME' for $VM_NAME${NC}"
            else
                echo -e "${RED}Failed to create snapshot for $VM_NAME${NC}"
            fi
        ) &
        
        # Save the PID of the background process
        echo $! >> "$TEMP_PIDS_FILE"
    done
    
    # Display progress information
    echo -e "${CYAN}Snapshots are being created in parallel. This might take a moment...${NC}"
    echo -e "${CYAN}You will be notified when all snapshots are complete.${NC}"
    
    # Wait for all snapshot processes to complete
    if [ -f "$TEMP_PIDS_FILE" ]; then
        while read -r PID; do
            if kill -0 $PID 2>/dev/null; then
                wait $PID
            fi
        done < "$TEMP_PIDS_FILE"
        rm "$TEMP_PIDS_FILE"
    fi
    
    echo -e "${GREEN}All snapshots have been created.${NC}"
    
    # Provide some tips for better snapshot performance
    echo -e "${CYAN}Tips for better snapshot performance:${NC}"
    echo -e "${CYAN}1. Consider closing other applications while creating snapshots${NC}"
    echo -e "${CYAN}2. If you need more frequent snapshots, use VMware Fusion's AutoProtect feature${NC}"
    echo -e "${CYAN}3. Periodically remove old snapshots to improve VM performance${NC}"
}

# List snapshots for all VMs
list_snapshots() {
    print_header "Listing snapshots for all VMs"
    
    # Check if VM directory exists
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    # Get list of VMs
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -maxdepth 1 -name "*.vmwarevm" -type d)
    
    if [ -z "$VMWARE_VM_DIRS" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    echo -e "${CYAN}Found $(echo "$VMWARE_VM_DIRS" | wc -l | tr -d ' ') VMs${NC}"
    
    # Get VM names (sorted)
    VM_NAMES=()
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VM_NAMES+=("$VM_NAME")
    done
    
    # Sort VM names
    IFS=$'\n' VM_NAMES=($(sort <<<"${VM_NAMES[*]}"))
    unset IFS
    
    # Collect snapshot data
    echo -e "${CYAN}Scanning VMs for snapshots...${NC}"
    ALL_SNAPSHOTS=()
    
    # Create temporary files to store VM data
    VM_DATA_FILE=$(mktemp)
    
    # First pass - collect all unique snapshots
    for VM_NAME in "${VM_NAMES[@]}"; do
        # Find VM directory
        VM_DIR=""
        for DIR in $VMWARE_VM_DIRS; do
            if [ "$(basename "$DIR" | sed 's/\.vmwarevm//')" = "$VM_NAME" ]; then
                VM_DIR="$DIR"
                break
            fi
        done
        
        VMX_FILE="$VM_DIR/$VM_NAME.vmx"
        
        if [ ! -f "$VMX_FILE" ]; then
            continue
        fi
        
        # Check if VM is running (store as "running" or "stopped")
        VM_STATUS="stopped"
        if vmrun -T fusion list | grep -q "$VMX_FILE" 2>/dev/null; then
            VM_STATUS="running"
        fi
        
        # Get snapshots
        SNAPSHOTS_RAW=$(vmrun -T fusion listSnapshots "$VMX_FILE" 2>&1)
        
        if [[ "$SNAPSHOTS_RAW" == *"Error"* ]]; then
            # Store VM data: name,status,snapshot_status
            echo "$VM_NAME,$VM_STATUS,error" >> "$VM_DATA_FILE"
        elif [[ "$SNAPSHOTS_RAW" == *"Total snapshots: 0"* ]] || [[ "$SNAPSHOTS_RAW" == *"No snapshots"* ]]; then
            echo "$VM_NAME,$VM_STATUS,none" >> "$VM_DATA_FILE"
        else
            # Extract snapshot names
            SNAPSHOTS=$(echo "$SNAPSHOTS_RAW" | grep -v "Total snapshots")
            
            # Store VM with its snapshot list
            echo "$VM_NAME,$VM_STATUS,has_snapshots,$SNAPSHOTS" >> "$VM_DATA_FILE"
            
            # Add to ALL_SNAPSHOTS array if not already there
            while IFS= read -r SNAPSHOT; do
                if [ -n "$SNAPSHOT" ]; then
                    # Add to unique snapshots list
                    FOUND=0
                    for s in "${ALL_SNAPSHOTS[@]}"; do
                        if [ "$s" = "$SNAPSHOT" ]; then
                            FOUND=1
                            break
                        fi
                    done
                    if [ $FOUND -eq 0 ]; then
                        ALL_SNAPSHOTS+=("$SNAPSHOT")
                    fi
                fi
            done <<< "$SNAPSHOTS"
        fi
    done
    
    # Sort snapshots alphabetically
    if [ ${#ALL_SNAPSHOTS[@]} -gt 0 ]; then
        IFS=$'\n' ALL_SNAPSHOTS=($(sort <<<"${ALL_SNAPSHOTS[*]}"))
        unset IFS
    fi
    
    echo -e "${CYAN}Found ${#ALL_SNAPSHOTS[@]} unique snapshots${NC}"
    
    if [ ${#ALL_SNAPSHOTS[@]} -eq 0 ]; then
        echo -e "${CYAN}No snapshots found for any VMs.${NC}"
        rm -f "$VM_DATA_FILE"
        return
    fi
    
    # Print table header
    echo -e "\n${BLUE}=== VM Snapshot Table ===${NC}"
    
    # Calculate column widths
    VM_COL_WIDTH=15  # VM name column width
    SNAP_COL_WIDTH=11  # Snapshot column width
    
    # Build top border
    printf "+-%${VM_COL_WIDTH}s-+" "-" | tr " " "-"
    for ((i=0; i<${#ALL_SNAPSHOTS[@]}; i++)); do
        printf -- "-%${SNAP_COL_WIDTH}s-+" "-" | tr " " "-"
    done
    printf "\n"
    
    # Build header row
    printf "| ${CYAN}%-${VM_COL_WIDTH}s${NC} |" "VM Name"
    for SNAPSHOT in "${ALL_SNAPSHOTS[@]}"; do
        # Truncate long names
        if [ ${#SNAPSHOT} -gt $((SNAP_COL_WIDTH-1)) ]; then
            DISP_NAME="${SNAPSHOT:0:$((SNAP_COL_WIDTH-3))}..."
        else
            DISP_NAME="$SNAPSHOT"
        fi
        printf " ${CYAN}%-${SNAP_COL_WIDTH}s${NC}|" "$DISP_NAME"
    done
    printf "\n"
    
    # Build middle border
    printf "+-%${VM_COL_WIDTH}s-+" "-" | tr " " "-"
    for ((i=0; i<${#ALL_SNAPSHOTS[@]}; i++)); do
        printf -- "-%${SNAP_COL_WIDTH}s-+" "-" | tr " " "-"
    done
    printf "\n"
    
    # Build data rows
    while IFS="," read -r VM_NAME VM_STATUS SNAPSHOT_STATUS SNAPSHOT_DATA; do
        # VM name with color based on running status
        if [ "$VM_STATUS" = "running" ]; then
            printf "| ${GREEN}%-${VM_COL_WIDTH}s${NC} |" "$VM_NAME"
        else
            printf "| ${BLUE}%-${VM_COL_WIDTH}s${NC} |" "$VM_NAME"
        fi
        
        # Snapshot status cells
        for SNAPSHOT in "${ALL_SNAPSHOTS[@]}"; do
            if [ "$SNAPSHOT_STATUS" = "error" ]; then
                printf " ${RED}!%-$((SNAP_COL_WIDTH-1))s${NC}|" ""
            elif [ "$SNAPSHOT_STATUS" = "none" ]; then
                printf " ${RED}✖%-$((SNAP_COL_WIDTH-1))s${NC}|" ""
            elif [ "$SNAPSHOT_STATUS" = "has_snapshots" ]; then
                # Check if this specific snapshot exists
                if echo "$SNAPSHOT_DATA" | grep -q "^$SNAPSHOT$"; then
                    printf " ${GREEN}✓%-$((SNAP_COL_WIDTH-1))s${NC}|" ""
                else
                    printf " ${RED}✖%-$((SNAP_COL_WIDTH-1))s${NC}|" ""
                fi
            else
                # Default case - shouldn't get here
                printf " %-${SNAP_COL_WIDTH}s|" "?"
            fi
        done
        printf "\n"
    done < "$VM_DATA_FILE"
    
    # Build bottom border
    printf "+-%${VM_COL_WIDTH}s-+" "-" | tr " " "-"
    for ((i=0; i<${#ALL_SNAPSHOTS[@]}; i++)); do
        printf -- "-%${SNAP_COL_WIDTH}s-+" "-" | tr " " "-"
    done
    printf "\n"
    
    # Print legend
    echo -e "\n${BLUE}=== Legend ===${NC}"
    echo -e "${GREEN}✓${NC} = Snapshot exists"
    echo -e "${RED}✖${NC} = No snapshot"
    echo -e "${RED}!${NC} = Error getting snapshot data"
    echo -e "${GREEN}VM Name${NC} = VM is running"
    echo -e "${BLUE}VM Name${NC} = VM is powered off"
    
    # Print summary
    echo -e "\n${BLUE}=== Summary ===${NC}"
    
    # Count running VMs
    RUNNING_COUNT=$(grep ",running," "$VM_DATA_FILE" | wc -l | tr -d ' ')
    
    echo -e "VMs: ${#VM_NAMES[@]} (${GREEN}$RUNNING_COUNT running${NC}, ${BLUE}$((${#VM_NAMES[@]} - RUNNING_COUNT)) powered off${NC})"
    echo -e "Snapshots: ${#ALL_SNAPSHOTS[@]}"
    
    # Clean up
    rm -f "$VM_DATA_FILE"
    
    echo -e "\n${BLUE}=== VMware Fusion Tip ===${NC}"
    echo -e "View snapshots in VMware Fusion: VM > Virtual Machine > Snapshots (Shift+Cmd+S)"
}

# Function to show manual snapshot deletion instructions
show_manual_snapshot_instructions() {
    print_header "Manual Snapshot Deletion Instructions"
    
    echo -e "${CYAN}To manually delete snapshots using VMware Fusion Pro:${NC}"
    echo -e "\n${CYAN}Method 1: Using VMware Fusion UI${NC}"
    echo -e "1. Open VMware Fusion"
    echo -e "2. Select the VM from the Virtual Machine Library"
    echo -e "3. Click on 'Virtual Machine' in the menu bar"
    echo -e "4. Select 'Snapshots' (or press Shift+Command+S)"
    echo -e "5. In the Snapshots window, select the snapshot you want to delete"
    echo -e "6. Click the 'Delete' button"
    echo -e "7. Confirm the deletion"
    
    echo -e "\n${CYAN}Method 2: Using Terminal Commands${NC}"
    echo -e "1. List available VMs:"
    echo -e "   vmrun -T fusion list"
    echo -e "2. List snapshots for a specific VM:"
    echo -e "   vmrun -T fusion listSnapshots \"/path/to/vm.vmx\""
    echo -e "3. Delete a specific snapshot:"
    echo -e "   vmrun -T fusion deleteSnapshot \"/path/to/vm.vmx\" \"snapshot_name\""
    
    echo -e "\n${CYAN}Note: For VMs in our cluster, use:${NC}"
    echo -e "   VM_DIR=\"$VM_CLUSTER_DIR/vm_name.vmwarevm\""
    echo -e "   VMX_FILE=\"\$VM_DIR/vm_name.vmx\""
    echo -e "   vmrun -T fusion deleteSnapshot \"\$VMX_FILE\" \"snapshot_name\""
    
    echo -e "\n${CYAN}Important:${NC}"
    echo -e "- Sometimes snapshots can only be deleted when the VM is powered off"
    echo -e "- If you cannot delete a snapshot while the VM is running, shutdown the VM first"
    echo -e "- Deleting snapshots may take some time, especially for large VMs"
    echo -e "- VMware Fusion may need to consolidate disks after snapshot deletion"
}

# Function to delete a specific snapshot for a specific VM
delete_specific_snapshot() {
    print_header "Delete a Specific Snapshot"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        echo -e "${CYAN}Please create VMs first.${NC}"
        return
    fi
    
    # Get list of VMs
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -maxdepth 1 -name "*.vmwarevm" -type d)
    
    if [ -z "$VMWARE_VM_DIRS" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    # Select a VM
    echo -e "${CYAN}Available VMs:${NC}"
    VM_ARRAY=()
    i=1
    
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VM_ARRAY+=("$VM_DIR")
        echo -e "$i) $VM_NAME"
        i=$((i+1))
    done
    
    echo -e "${CYAN}Select a VM (1-$((i-1))):${NC}"
    read VM_SELECTION
    
    if ! [[ "$VM_SELECTION" =~ ^[0-9]+$ ]] || [ "$VM_SELECTION" -lt 1 ] || [ "$VM_SELECTION" -gt $((i-1)) ]; then
        echo -e "${RED}Invalid selection.${NC}"
        return
    fi
    
    VM_DIR=${VM_ARRAY[$((VM_SELECTION-1))]}
    VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
    VMX_FILE="$VM_DIR/$VM_NAME.vmx"
    
    # Check if VM is running
    VM_RUNNING=false
    if vmrun -T fusion list | grep -q "$VMX_FILE"; then
        VM_RUNNING=true
        echo -e "${CYAN}VM $VM_NAME is currently running.${NC}"
        echo -e "${CYAN}Some snapshots can only be deleted when the VM is powered off.${NC}"
        echo -e "${CYAN}Do you want to power off the VM first? (y/n)${NC}"
        read -p "" -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}Shutting down VM...${NC}"
            vmrun -T fusion stop "$VMX_FILE" soft || true
            sleep 10
            
            # Check if VM is still running
            if vmrun -T fusion list | grep -q "$VMX_FILE"; then
                echo -e "${RED}VM did not shutdown gracefully. Try force power off? (y/n)${NC}"
                read -p "" -n 1 -r
                echo
                
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    vmrun -T fusion stop "$VMX_FILE" hard || true
                    sleep 5
                    
                    if vmrun -T fusion list | grep -q "$VMX_FILE"; then
                        echo -e "${RED}Could not power off VM. Will try to delete snapshot anyway.${NC}"
                    else
                        VM_RUNNING=false
                    fi
                fi
            else
                VM_RUNNING=false
            fi
        fi
    fi
    
    # List snapshots for the selected VM
    echo -e "\n${CYAN}Listing snapshots for $VM_NAME...${NC}"
    SNAPSHOTS=$(vmrun -T fusion listSnapshots "$VMX_FILE" 2>&1 | grep -v "Total snapshots")
    
    if [[ "$SNAPSHOTS" == *"Error"* ]]; then
        echo -e "${RED}Error listing snapshots for $VM_NAME: $SNAPSHOTS${NC}"
        return
    elif [[ "$SNAPSHOTS" == *"No snapshots"* ]] || [ -z "$SNAPSHOTS" ]; then
        echo -e "${CYAN}No snapshots found for $VM_NAME${NC}"
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
    echo -e "${CYAN}Select a snapshot to delete (1-$((i-1))):${NC}"
    read SNAPSHOT_SELECTION
    
    if ! [[ "$SNAPSHOT_SELECTION" =~ ^[0-9]+$ ]] || [ "$SNAPSHOT_SELECTION" -lt 1 ] || [ "$SNAPSHOT_SELECTION" -gt $((i-1)) ]; then
        echo -e "${RED}Invalid selection.${NC}"
        return
    fi
    
    SELECTED_SNAPSHOT=${SNAPSHOT_ARRAY[$((SNAPSHOT_SELECTION-1))]}
    
    # Confirm deletion
    echo -e "${RED}Warning: This will delete the snapshot '$SELECTED_SNAPSHOT' for VM $VM_NAME.${NC}"
    echo -e "${CYAN}Are you sure you want to continue? (y/n)${NC}"
    read -p "" -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Deletion cancelled.${NC}"
        return
    fi
    
    # Delete the snapshot
    echo -e "${CYAN}Deleting snapshot '$SELECTED_SNAPSHOT' for $VM_NAME...${NC}"
    if ! vmrun -T fusion deleteSnapshot "$VMX_FILE" "$SELECTED_SNAPSHOT"; then
        echo -e "${RED}Failed to delete snapshot '$SELECTED_SNAPSHOT' for $VM_NAME${NC}"
        echo -e "${CYAN}This could be because:${NC}"
        echo -e "1. The snapshot is in use"
        echo -e "2. The VM is still running (some snapshots require VM to be powered off)"
        echo -e "3. There was an internal VMware Fusion error"
        echo -e "\n${CYAN}For manual deletion, use VMware Fusion UI or the following command:${NC}"
        echo -e "vmrun -T fusion deleteSnapshot \"$VMX_FILE\" \"$SELECTED_SNAPSHOT\""
    else
        echo -e "${GREEN}Successfully deleted snapshot '$SELECTED_SNAPSHOT' for $VM_NAME${NC}"
    fi
    
    # Start VM if it was running and we powered it off
    if [ "$VM_RUNNING" = true ] && ! vmrun -T fusion list | grep -q "$VMX_FILE"; then
        echo -e "${CYAN}Do you want to start the VM again? (y/n)${NC}"
        read -p "" -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}Starting VM...${NC}"
            vmrun -T fusion start "$VMX_FILE"
        fi
    fi
}

# Rollback to a snapshot
rollback_to_snapshot() {
    print_header "Rollback to snapshot"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        echo -e "${CYAN}Please create VMs first.${NC}"
        return
    fi
    
    # Get list of VMs
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -maxdepth 1 -name "*.vmwarevm" -type d)
    
    if [ -z "$VMWARE_VM_DIRS" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    # Select a VM for snapshot listing
    echo -e "${CYAN}Available VMs:${NC}"
    VM_ARRAY=()
    i=1
    
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VM_ARRAY+=("$VM_DIR")
        echo -e "$i) $VM_NAME"
        i=$((i+1))
    done
    
    echo -e "${CYAN}Select a VM to view snapshots (1-$((i-1))):${NC}"
    read VM_SELECTION
    
    if ! [[ "$VM_SELECTION" =~ ^[0-9]+$ ]] || [ "$VM_SELECTION" -lt 1 ] || [ "$VM_SELECTION" -gt $((i-1)) ]; then
        echo -e "${RED}Invalid selection.${NC}"
        return
    fi
    
    VM_DIR=${VM_ARRAY[$((VM_SELECTION-1))]}
    VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
    VMX_FILE="$VM_DIR/$VM_NAME.vmx"
    
    # List snapshots for the selected VM
    echo -e "\n${CYAN}Snapshots for $VM_NAME:${NC}"
    SNAPSHOTS=$(vmrun -T fusion listSnapshots "$VMX_FILE" 2>&1 | grep -v "Total snapshots")
    
    if [[ "$SNAPSHOTS" == *"Error"* ]]; then
        echo -e "${RED}Error listing snapshots for $VM_NAME: $SNAPSHOTS${NC}"
        return
    elif [[ "$SNAPSHOTS" == *"No snapshots"* ]] || [ -z "$SNAPSHOTS" ]; then
        echo -e "${CYAN}No snapshots found for $VM_NAME${NC}"
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
    echo -e "${CYAN}Select a snapshot to rollback to (1-$((i-1))):${NC}"
    read SNAPSHOT_SELECTION
    
    if ! [[ "$SNAPSHOT_SELECTION" =~ ^[0-9]+$ ]] || [ "$SNAPSHOT_SELECTION" -lt 1 ] || [ "$SNAPSHOT_SELECTION" -gt $((i-1)) ]; then
        echo -e "${RED}Invalid selection.${NC}"
        return
    fi
    
    SELECTED_SNAPSHOT=${SNAPSHOT_ARRAY[$((SNAPSHOT_SELECTION-1))]}
    
    # Confirm rollback
    echo -e "${RED}Warning: This will revert the VM to the selected snapshot state. All changes since then will be lost.${NC}"
    echo -e "${CYAN}Are you sure you want to rollback $VM_NAME to snapshot '$SELECTED_SNAPSHOT'? (y/n)${NC}"
    read -p "" -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Rollback cancelled.${NC}"
        return
    fi
    
    # First check VM state
    VM_RUNNING=false
    if vmrun -T fusion list | grep -q "$VMX_FILE"; then
        VM_RUNNING=true
        echo -e "${CYAN}Stopping VM...${NC}"
        vmrun -T fusion stop "$VMX_FILE" soft || true
        sleep 10  # Give more time for VM to shutdown
        
        # Check if VM is still running, try hard stop if needed
        if vmrun -T fusion list | grep -q "$VMX_FILE"; then
            echo -e "${RED}VM did not stop gracefully. Trying force power off...${NC}"
            vmrun -T fusion stop "$VMX_FILE" hard || true
            sleep 5
            
            # If VM is still running, cannot proceed
            if vmrun -T fusion list | grep -q "$VMX_FILE"; then
                echo -e "${RED}Failed to stop VM. Cannot revert to snapshot.${NC}"
                return
            fi
        fi
    fi
    
    # Rollback to snapshot
    echo -e "${CYAN}Rolling back to snapshot...${NC}"
    if ! vmrun -T fusion revertToSnapshot "$VMX_FILE" "$SELECTED_SNAPSHOT"; then
        echo -e "${RED}Failed to revert to snapshot. Check VMware Fusion logs for details.${NC}"
        # Try to restart VM if it was running before
        if [ "$VM_RUNNING" = true ]; then
            echo -e "${CYAN}Attempting to restart VM in its previous state...${NC}"
            vmrun -T fusion start "$VMX_FILE" || true
        fi
        return
    fi
    
    # Start VM if it was running before
    if [ "$VM_RUNNING" = true ]; then
        echo -e "${CYAN}Starting VM...${NC}"
        vmrun -T fusion start "$VMX_FILE" || echo -e "${RED}Failed to start VM after rollback${NC}"
    fi
    
    echo -e "${GREEN}VM $VM_NAME has been rolled back to snapshot '$SELECTED_SNAPSHOT'.${NC}"
}

# Delete a snapshot from all VMs
delete_all_snapshots() {
    print_header "Delete a snapshot from all VMs"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${RED}Error: VM directory not found: $VM_CLUSTER_DIR${NC}"
        echo -e "${CYAN}Please create VMs first.${NC}"
        return
    fi
    
    # Get list of VMs
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -maxdepth 1 -name "*.vmwarevm" -type d)
    
    if [ -z "$VMWARE_VM_DIRS" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    # Get unique snapshot names
    echo -e "${CYAN}Getting available snapshots across all VMs...${NC}"
    ALL_SNAPSHOTS=()
    
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VMX_FILE="$VM_DIR/$VM_NAME.vmx"
        
        if [ ! -f "$VMX_FILE" ]; then
            echo -e "${RED}Error: VMX file not found for $VM_NAME${NC}"
            continue
        fi
        
        # Use vmrun to list snapshots
        SNAPSHOTS=$(vmrun -T fusion listSnapshots "$VMX_FILE" 2>/dev/null | grep -v "Total snapshots" || echo "")
        
        # Add unique snapshots to ALL_SNAPSHOTS array
        while IFS= read -r SNAPSHOT; do
            if [ -n "$SNAPSHOT" ]; then
                # Check if snapshot is already in array
                if ! echo "${ALL_SNAPSHOTS[@]}" | grep -q "^$SNAPSHOT$"; then
                    ALL_SNAPSHOTS+=("$SNAPSHOT")
                fi
            fi
        done <<< "$SNAPSHOTS"
    done
    
    # Check if there are any snapshots
    if [ ${#ALL_SNAPSHOTS[@]} -eq 0 ]; then
        echo -e "${CYAN}No snapshots found for any VMs.${NC}"
        return
    fi
    
    # Sort the snapshots alphabetically
    IFS=$'\n' ALL_SNAPSHOTS=($(sort <<<"${ALL_SNAPSHOTS[*]}"))
    unset IFS
    
    # Display available snapshots
    echo -e "${CYAN}Available snapshots:${NC}"
    for i in "${!ALL_SNAPSHOTS[@]}"; do
        echo -e "$((i+1))) ${ALL_SNAPSHOTS[$i]}"
    done
    
    # Let user select a snapshot to delete
    echo -e "${CYAN}Select a snapshot to delete (1-${#ALL_SNAPSHOTS[@]}):${NC}"
    read SNAPSHOT_SELECTION
    
    if ! [[ "$SNAPSHOT_SELECTION" =~ ^[0-9]+$ ]] || [ "$SNAPSHOT_SELECTION" -lt 1 ] || [ "$SNAPSHOT_SELECTION" -gt ${#ALL_SNAPSHOTS[@]} ]; then
        echo -e "${RED}Invalid selection.${NC}"
        return
    fi
    
    SELECTED_SNAPSHOT=${ALL_SNAPSHOTS[$((SNAPSHOT_SELECTION-1))]}
    
    # Confirm deletion
    echo -e "${RED}Warning: This will delete the snapshot '$SELECTED_SNAPSHOT' from ALL VMs that have it.${NC}"
    echo -e "${RED}This operation cannot be undone.${NC}"
    echo -e "${CYAN}Are you sure you want to continue? (y/n)${NC}"
    read -p "" -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Deletion cancelled.${NC}"
        return
    fi
    
    # Use temporary file to track process IDs
    TEMP_PIDS_FILE=$(mktemp)
    
    # Check for each VM if it has the snapshot and delete it
    echo -e "${CYAN}Deleting snapshot '$SELECTED_SNAPSHOT' from all VMs...${NC}"
    
    # Keep track of successful and failed deletions
    SUCCESSFUL_DELETIONS=()
    FAILED_DELETIONS=()
    
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VMX_FILE="$VM_DIR/$VM_NAME.vmx"
        
        if [ ! -f "$VMX_FILE" ]; then
            echo -e "${RED}Error: VMX file not found for $VM_NAME${NC}"
            continue
        fi
        
        # Check if VM has the snapshot
        HAS_SNAPSHOT=$(vmrun -T fusion listSnapshots "$VMX_FILE" 2>/dev/null | grep -v "Total snapshots" | grep -x "$SELECTED_SNAPSHOT" || echo "")
        
        if [ -n "$HAS_SNAPSHOT" ]; then
            echo -e "${CYAN}VM $VM_NAME has the snapshot. Deleting...${NC}"
            
            # Delete snapshot in background process for parallel processing
            (
                # Check if VM is running
                if vmrun -T fusion list | grep -q "$VMX_FILE"; then
                    echo -e "${CYAN}VM $VM_NAME is running. Attempting to delete snapshot...${NC}"
                else
                    echo -e "${CYAN}VM $VM_NAME is not running. Deleting snapshot...${NC}"
                fi
                
                # Delete snapshot
                if vmrun -T fusion deleteSnapshot "$VMX_FILE" "$SELECTED_SNAPSHOT"; then
                    echo -e "${GREEN}Successfully deleted snapshot '$SELECTED_SNAPSHOT' from $VM_NAME${NC}"
                    # Using a file to record successful operations for parallel processes
                    echo "$VM_NAME" >> /tmp/successful_deletions_$$
                else
                    echo -e "${RED}Failed to delete snapshot '$SELECTED_SNAPSHOT' from $VM_NAME${NC}"
                    # Using a file to record failed operations for parallel processes
                    echo "$VM_NAME" >> /tmp/failed_deletions_$$
                fi
            ) &
            
            # Save the PID of the background process
            echo $! >> "$TEMP_PIDS_FILE"
        else
            echo -e "${CYAN}VM $VM_NAME does not have the snapshot. Skipping.${NC}"
        fi
    done
    
    # Create the temporary files if they don't exist
    touch /tmp/successful_deletions_$$
    touch /tmp/failed_deletions_$$
    
    # Display progress information
    echo -e "${CYAN}Snapshot deletion is running in parallel. This might take a moment...${NC}"
    
    # Wait for all deletion processes to complete
    if [ -f "$TEMP_PIDS_FILE" ]; then
        while read -r PID; do
            if kill -0 $PID 2>/dev/null; then
                wait $PID
            fi
        done < "$TEMP_PIDS_FILE"
        rm "$TEMP_PIDS_FILE"
    fi
    
    # Collect results
    if [ -f "/tmp/successful_deletions_$$" ]; then
        SUCCESSFUL_DELETIONS=($(cat /tmp/successful_deletions_$$))
        rm /tmp/successful_deletions_$$
    fi
    
    if [ -f "/tmp/failed_deletions_$$" ]; then
        FAILED_DELETIONS=($(cat /tmp/failed_deletions_$$))
        rm /tmp/failed_deletions_$$
    fi
    
    # Show summary
    echo -e "\n${CYAN}Snapshot Deletion Summary:${NC}"
    echo -e "Snapshot: $SELECTED_SNAPSHOT"
    echo -e "Successfully deleted from: ${#SUCCESSFUL_DELETIONS[@]} VMs"
    echo -e "Failed to delete from: ${#FAILED_DELETIONS[@]} VMs"
    
    if [ ${#SUCCESSFUL_DELETIONS[@]} -gt 0 ]; then
        echo -e "\n${GREEN}Successfully deleted from:${NC}"
        for VM in "${SUCCESSFUL_DELETIONS[@]}"; do
            echo -e "- $VM"
        done
    fi
    
    if [ ${#FAILED_DELETIONS[@]} -gt 0 ]; then
        echo -e "\n${RED}Failed to delete from:${NC}"
        for VM in "${FAILED_DELETIONS[@]}"; do
            echo -e "- $VM"
        done
        
        echo -e "\n${CYAN}Note: Some VMs may require being powered off before deleting snapshots.${NC}"
        echo -e "${CYAN}You can power off VMs from the main menu and try again.${NC}"
    fi
}

# Deploy Kubernetes workflow
deploy_k8s_workflow() {
    print_header "Deploying Kubernetes Cluster Workflow"
    
    # Check prerequisites
    check_prerequisites
    
    # Ask for confirmation
    echo -e "${CYAN}This workflow will:${NC}"
    echo -e "1. Remove any existing Kubernetes VMs"
    echo -e "2. Create new VMs for the Kubernetes cluster"
    echo -e "3. Set up Terraform"
    echo -e "4. Deploy Kubernetes"
    echo -e "\n${RED}WARNING: This will delete any existing VMs in $VM_CLUSTER_DIR${NC}"
    echo -e "${CYAN}Do you want to continue? (y/n)${NC}"
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
    echo -e "${CYAN}VMs have been created and Terraform has been set up.${NC}"
    echo -e "${CYAN}Do you want to proceed with deploying Kubernetes? (y/n)${NC}"
    read -p "" -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}Kubernetes deployment skipped. You can deploy it later by running this script.${NC}"
        return
    fi
    
    # Deploy Kubernetes
    deploy_kubernetes
    
    # Display cluster information
    display_cluster_info
}

# Function to manage snapshots submenu
manage_snapshots_submenu() {
    while true; do
        print_header "Snapshot Management Submenu"
        echo -e "1) Create snapshot for all VMs"
        echo -e "2) List snapshots for all VMs"
        echo -e "3) Rollback to a specific snapshot"
        echo -e "4) Delete a snapshot from all VMs"
        echo -e "5) Delete a specific snapshot from a specific VM"
        echo -e "6) Show manual snapshot deletion instructions"
        echo -e "0) Return to main menu"
        echo -e "\n${CYAN}Enter your choice:${NC}"
        
        read -p "" SNAPSHOT_CHOICE
        
        case $SNAPSHOT_CHOICE in
            1)
                create_snapshots
                ;;
            2)
                list_snapshots
                ;;
            3)
                rollback_to_snapshot
                ;;
            4)
                delete_all_snapshots
                ;;
            5)
                delete_specific_snapshot
                ;;
            6)
                show_manual_snapshot_instructions
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                ;;
        esac
        
        echo -e "\n${CYAN}Press Enter to continue...${NC}"
        read
    done
}

# Main menu
display_menu() {
    print_header "Kubernetes Cluster Management Menu"
    echo -e "1) Deploy Kubernetes Cluster (Full Workflow)"
    echo -e "2) Create all VMs and basic configuration"
    echo -e "3) Check VM status and network configuration"
    echo -e "4) Manage snapshots (submenu)"
    echo -e "5) Delete all VMs"
    echo -e "6) Deploy Kubernetes on existing VMs"
    echo -e "7) Power on all VMs"
    echo -e "8) Shutdown all VMs"
    echo -e "9) Update VM IP addresses"
    echo -e "10) View documentation"
    echo -e "0) Exit"
    echo -e "\n${CYAN}Enter your choice:${NC}"
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
                manage_snapshots_submenu
                ;;
            5)
                remove_existing_vms
                ;;
            6)
                if [ ! -f "vm-ips.env" ]; then
                    echo -e "${RED}Error: vm-ips.env not found. Please create VMs first.${NC}"
                else
                    setup_terraform && deploy_kubernetes && display_cluster_info
                fi
                ;;
            7)
                power_on_all_vms
                ;;
            8)
                shutdown_all_vms
                ;;
            9)
                update_vm_ips
                ;;
            10)
                show_documentation
                ;;
            0)
                echo -e "${GREEN}Exiting...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                ;;
        esac
        
        echo -e "\n${CYAN}Press Enter to continue...${NC}"
        read
    done
}

# Run main function
main
