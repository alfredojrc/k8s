#!/usr/bin/env bash
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

# Optional APT Cache Server IP (leave empty to disable)
# Can be overridden by environment variable K8S_APT_CACHE_SERVER_IP
APT_CACHE_SERVER_IP="${K8S_APT_CACHE_SERVER_IP:-192.168.130.153}"

# [LOCKED_CONFIG: Do not modify these critical settings]
# Configuration
# Allow overriding defaults via environment variables
PROJECT_DIR="${K8S_PROJECT_DIR:-$HOME/godz/k8s}"
VM_CLUSTER_DIR="${K8S_VM_CLUSTER_DIR:-/Users/alf/VMs/k8s_cluster}"
BASE_IMAGE_PATH="${K8S_BASE_IMAGE_PATH:-$PROJECT_DIR/base_images/noble-server-cloudimg-arm64.img}"
BASE_IMAGE_URL="${K8S_BASE_IMAGE_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img}"
# Use a more secure approach for password
PASSWORD_FILE="${K8S_PASSWORD_FILE:-$HOME/.k8s_password}"
# [END_LOCKED_CONFIG]

# VM Creation Configuration
VM_DISK_SIZE=${K8S_VM_DISK_SIZE:-40G}

# VM Template Configuration
SSH_PUBLIC_KEY="${K8S_SSH_PUBLIC_KEY:-$HOME/.ssh/id_ed25519.pub}"

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
    
    # Ensure we are in the project directory
    cd "$PROJECT_DIR" || { echo -e "${RED}Error: Failed to change directory to $PROJECT_DIR${NC}"; exit 1; }

    # Get list of running VMs managed by this script
    # Filter by VM_CLUSTER_DIR to avoid listing unrelated VMs
    RUNNING_VMS=$(vmrun -T fusion list | grep "$VM_CLUSTER_DIR" | grep -v "Total running VMs" || true)
    
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
    
    echo -e "${CYAN}Creating VM disk for $VM_NAME from base image...${NC}" >&2
    # First convert to qcow2 format (better handling of conversion)
    TEMP_QCOW2="$VM_DIR/temp_disk.qcow2"
    echo -e "${CYAN}Converting raw image to qcow2 format...${NC}" >&2
    qemu-img convert -f raw -O qcow2 "$BASE_IMAGE_PATH" "$TEMP_QCOW2"

    # Resize the qcow2 image
    echo -e "${CYAN}Resizing disk image to $VM_DISK_SIZE...${NC}" >&2
    qemu-img resize "$TEMP_QCOW2" $VM_DISK_SIZE

    # Convert qcow2 to vmdk for VMware
    echo -e "${CYAN}Converting to vmdk format...${NC}" >&2
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
    # Accept APT Cache IP as an argument
    local apt_cache_ip=$4
    local CLOUD_INIT_ISO="$VM_DIR/$VM_NAME-cloud-init.iso"
    
    echo -e "${CYAN}Creating cloud-init configuration for $VM_NAME...${NC}"

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
  - open-vm-tools # Add VMware Tools for vmrun commands
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
  # Configure APT proxy if IP is provided
  $( [ -n "$apt_cache_ip" ] && echo "  - echo 'Acquire::http::Proxy \"http://$apt_cache_ip:3142\";' > /etc/apt/apt.conf.d/01proxy" || echo "")
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
    
    cd "$PROJECT_DIR" || { echo -e "${RED}Error: Failed to change directory to $PROJECT_DIR${NC}"; exit 1; }

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
    
    local found_ips=0
    local warned_vms=0

    # Get IP for each VM found in the cluster directory
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VMX_FILE="$VM_DIR/$VM_NAME.vmx"
        
        echo -e "${CYAN}Checking status for VM: $VM_NAME${NC}"
        
        if [ ! -f "$VMX_FILE" ]; then
            echo -e "${RED}Error: VMX file not found for $VM_NAME${NC}"
            continue
        fi
        
        # Check if VM is running
        if vmrun -T fusion list | grep -q -F "$VMX_FILE"; then
            echo -e "${CYAN}VM $VM_NAME is running. Getting IP address...${NC}"
            VM_IP=$(vmrun -T fusion getGuestIPAddress "$VMX_FILE" -wait 2>/dev/null || echo "")
            
            # Validate that we got a valid IP address
            if [[ $VM_IP =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$ ]]; then
                echo -e "${GREEN}VM $VM_NAME IP address: $VM_IP${NC}"
                
                # Format name for vm-ips.env
                ENV_NAME=$(echo "$VM_NAME" | sed 's/k8s-//g')_ip
                
                # Add IP to vm-ips.env
                echo "$ENV_NAME = \\\"$VM_IP\\\"" >> vm-ips.env
                found_ips=$((found_ips + 1))
            else
                echo -e "${RED}Could not get a valid IP address for running VM $VM_NAME. VMware Tools might not be running or network is not ready.${NC}"
                warned_vms=$((warned_vms + 1))
            fi
        else
            echo -e "${CYAN}VM $VM_NAME is not running. Skipping IP retrieval.${NC}"
            warned_vms=$((warned_vms + 1))
        fi
    done
    
    # Check if all required VMs have entries in the generated file
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
    
    echo -e "\\n${CYAN}Creating VM: $vm_name (Memory: ${memory}MB, CPUs: ${cpus})${NC}" >&2
    
    # Setup VM directory
    local VM_DIR="$VM_CLUSTER_DIR/$vm_name.vmwarevm"
    local VMX_FILE="$VM_DIR/$vm_name.vmx"
    
    # Delete existing VM if it exists (ensure it's stopped first)
    if vmrun -T fusion list | grep -q -F "$VMX_FILE"; then
        echo "Stopping existing VM $vm_name..." >&2
        vmrun -T fusion stop "$VMX_FILE" hard || { 
            echo -e "${RED}Error: Failed to stop existing VM $vm_name. Please stop it manually.${NC}" >&2; 
            # Decide if we should exit or continue. Exiting is safer.
            exit 1; 
        }
        # Short pause after stopping
        sleep 5 
    fi
    
    if [ -d "$VM_DIR" ]; then
        echo "Deleting existing VM directory: $VM_DIR" >&2
        rm -rf "$VM_DIR"
    fi
    
    # Create VM directory
    echo "Creating VM directory: $VM_DIR" >&2
    mkdir -p "$VM_DIR"
    
    # Load password
    if [ ! -f "$PASSWORD_FILE" ]; then
        echo -e "${RED}Error: Password file not found at $PASSWORD_FILE${NC}" >&2
        exit 1
    fi
    PASSWORD=$(cat "$PASSWORD_FILE")
    
    # Create VM components
    # Use full path for BASE_IMAGE_PATH just in case CWD changes unexpectedly elsewhere
    # (though it shouldn't in this flow)
    create_vm_disk "$VM_DIR" "$vm_name" || { echo -e "${RED}Error creating disk for $vm_name${NC}" >&2; exit 1; }
    create_cloud_init_iso "$VM_DIR" "$vm_name" "$PASSWORD" "$APT_CACHE_SERVER_IP" || { echo -e "${RED}Error creating cloud-init ISO for $vm_name${NC}" >&2; exit 1; }
    create_vmx_file "$VM_DIR" "$vm_name" "$memory" "$cpus" || { echo -e "${RED}Error creating VMX file for $vm_name${NC}" >&2; exit 1; }
    
    # Start the VM
    echo -e "${CYAN}Starting VM $vm_name...${NC}" >&2
    vmrun -T fusion start "$VMX_FILE" || { echo -e "${RED}Error starting VM $vm_name${NC}" >&2; exit 1; }
    
    echo -e "${GREEN}VM $vm_name created and started successfully!${NC}" >&2
    echo -e "${CYAN}Waiting for VM $vm_name to boot and get an IP address...${NC}" >&2
    
    # Wait for VM to boot and get IP address
    local VM_IP=""
    local MAX_ATTEMPTS=30 # Increased attempts
    local ATTEMPT=0
    
    while [ -z "$VM_IP" ] && [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        ATTEMPT=$((ATTEMPT+1))
        echo -e "${CYAN}Attempting to get IP for $vm_name ($ATTEMPT/$MAX_ATTEMPTS)...${NC}" >&2
        VM_IP=$(vmrun -T fusion getGuestIPAddress "$VMX_FILE" -wait 2>/dev/null || echo "")
        # Basic validation within the loop
        if [[ $VM_IP =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$ ]]; then
             echo -e "${GREEN}Got IP for $vm_name: $VM_IP${NC}" >&2
             break # Exit loop on success
        else
             VM_IP="" # Reset IP if invalid
             sleep 10
        fi
    done
    
    if [ -z "$VM_IP" ]; then
        echo -e "${RED}Failed to get IP address for $vm_name after $MAX_ATTEMPTS attempts${NC}" >&2
        echo -e "${RED}Check VMware Tools status inside the VM.${NC}" >&2
        # Attempt to stop the VM before exiting? Maybe not, let user handle it.
        exit 1
    fi
    
    # Wait for SSH to be available
    echo -e "${CYAN}Waiting for SSH on $vm_name ($VM_IP) to be available...${NC}" >&2
    local SSH_AVAILABLE=false
    local SSH_ATTEMPTS=0
    local MAX_SSH_ATTEMPTS=18 # Increased attempts
    
    while [ "$SSH_AVAILABLE" = false ] && [ $SSH_ATTEMPTS -lt $MAX_SSH_ATTEMPTS ]; do
        SSH_ATTEMPTS=$((SSH_ATTEMPTS+1))
        echo -e "${CYAN}Checking SSH connection to $vm_name ($ATTEMPTS/$MAX_SSH_ATTEMPTS)...${NC}" >&2
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes ubuntu@$VM_IP "echo SSH connection successful" &>/dev/null; then
            SSH_AVAILABLE=true
            echo -e "${GREEN}SSH connection to $vm_name successful${NC}" >&2
        else
            sleep 10
        fi
    done
    
    if [ "$SSH_AVAILABLE" = false ]; then
        echo -e "${RED}Failed to establish SSH connection to $vm_name after $MAX_SSH_ATTEMPTS attempts${NC}" >&2
        echo -e "${RED}Check SSH service and firewall settings inside the VM.${NC}" >&2
        exit 1
    fi
    
    # Install basic packages (optional, could be moved to cloud-init if preferred)
    # Redirecting output to /dev/null for cleaner parallel execution logs
    echo -e "${CYAN}Installing basic packages on $vm_name...${NC}" >&2
    ssh -o StrictHostKeyChecking=no -o BatchMode=yes ubuntu@$VM_IP "sudo apt-get update > /dev/null && sudo apt-get install -y neovim tmux bash-completion curl wget htop net-tools > /dev/null" || {
        echo -e "${RED}Failed to install basic packages on $vm_name${NC}" >&2
        # Decide if this is critical, maybe just warn
        # exit 1
    }
    
    # Output the IP address to stdout for capture
    echo "$VM_IP"
}

# [LOCKED_FUNCTION: Do not modify the VM creation process] - Implementing Staggered Parallel Launch
# Function to create all VMs with staggered parallel launch
create_vms() {
    print_header "Creating VMs (Staggered Parallel Launch)"
    
    # Create VM cluster directory if it doesn't exist
    mkdir -p "$VM_CLUSTER_DIR"
    
    # Change to project directory
    cd "$PROJECT_DIR" || { echo -e "${RED}Error: Failed to change directory to $PROJECT_DIR${NC}"; exit 1; }
    
    # Create directory for temporary VM IP files and ensure it's clean
    mkdir -p generated/ips
    rm -f generated/ips/*
    
    # Create empty vm-ips.env file first, ready for population
    rm -f vm-ips.env
    touch vm-ips.env
    
    # Define VMs to be created in order: name:memory:cpus
    local vms_to_create_ordered=(
        "haproxy1:2048:2"
        "haproxy2:2048:2"
        "k8s-master1:4096:4"
        "k8s-master2:4096:4"
        "k8s-master3:4096:4"
        "k8s-worker1:4096:4"
        "k8s-worker2:4096:4"
    )

    declare -a pids
    declare -a vm_names_ordered # Keep track of the order jobs were started
    local total_vms=${#vms_to_create_ordered[@]}
    local current_vm_index=0

    echo -e "${CYAN}Launching VM creation jobs with 2-second stagger...${NC}"
    for vm_definition in "${vms_to_create_ordered[@]}"; do
        current_vm_index=$((current_vm_index + 1))
        # Parse the definition string
        IFS=':' read -r vm_name memory cpus <<< "$vm_definition"
        
        echo -e "${BLUE}Launching creation for VM $current_vm_index/$total_vms: $vm_name...${NC}"
        # Run create_single_vm in the background
        # Redirect stdout (the IP) to a temporary file
        # Redirect stderr to a log file per VM for easier debugging
        create_single_vm "$vm_name" "$memory" "$cpus" > "generated/ips/${vm_name}.ip" 2> "generated/ips/${vm_name}.log" &
        pids+=($!) # Store the PID of the background job
        vm_names_ordered+=("$vm_name") # Store the name in the order launched

        # Add delay between launches, except after the last VM
        if [ $current_vm_index -lt $total_vms ]; then
            echo -e "${CYAN}Waiting 2 seconds before launching next VM...${NC}"
            sleep 2
        fi
    done

    echo -e "${CYAN}All VM creation jobs launched. Waiting for completion...${NC}"
    local all_success=true
    local failed_vms=()
    local success_vms=()

    # Wait for all background jobs to complete
    for i in "${!pids[@]}"; do
        pid=${pids[$i]}
        vm_name=${vm_names_ordered[$i]}
        if wait "$pid"; then
            echo -e "${GREEN}VM creation job for $vm_name (PID $pid) completed successfully.${NC}"
            success_vms+=("$vm_name")
        else
            echo -e "${RED}VM creation job for $vm_name (PID $pid) failed. Check logs: generated/ips/${vm_name}.log${NC}"
            all_success=false
            failed_vms+=("$vm_name")
        fi
    done

    if [ "$all_success" = false ]; then
        echo -e "${RED}One or more VM creation jobs failed: ${failed_vms[*]}${NC}"
        echo -e "${RED}Please check individual logs in generated/ips/ for details.${NC}"
        # Exiting here because continuing is likely problematic
        exit 1
    fi

    # Consolidate IPs from successful VMs
    echo -e "${CYAN}Consolidating IP addresses into vm-ips.env...${NC}"
    for vm_name in "${vm_names_ordered[@]}"; do # Iterate in launch order for potentially ordered IPs
        # Check if this VM was successful before trying to get its IP
        local vm_successful=false
        for successful_vm in "${success_vms[@]}"; do
            if [[ "$vm_name" == "$successful_vm" ]]; then
                vm_successful=true
                break
            fi
        done
        
        if ! $vm_successful; then
            echo -e "${CYAN}Skipping IP consolidation for failed VM: $vm_name${NC}"
            continue
        fi
        
        ip_file="generated/ips/${vm_name}.ip"
        if [ -f "$ip_file" ]; then
            ip=$(cat "$ip_file")
            # Validate IP read from file
            if [[ $ip =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$ ]]; then
                env_name=$(echo "$vm_name" | sed \'s/k8s-//g\')_ip
                echo "$env_name = \\\"$ip\\\"" >> vm-ips.env
                echo -e "${GREEN}Added IP for $vm_name to vm-ips.env${NC}"
            else
                echo -e "${RED}Warning: Invalid IP found in $ip_file for successful VM $vm_name: '$ip'${NC}"
                 # Consider adding to failed_vms or marking check_failed=true?
            fi
        else
             echo -e "${RED}Warning: IP file $ip_file not found for successful VM $vm_name${NC}"
        fi
    done

    # Clean up temporary IP and log files (optional)
    # echo -e "${CYAN}Cleaning up temporary IP/log files...${NC}"
    # rm -f generated/ips/*.ip generated/ips/*.log

    # Check if vm-ips.env was created (it should exist even if empty)
    if [ ! -f "vm-ips.env" ]; then
        echo -e "${RED}Critical Error: vm-ips.env was not created.${NC}"
        exit 1
    fi
    
    # Verify that all *required* VMs have valid entries in vm-ips.env
    local check_failed=false
    required_vms=("haproxy1_ip" "haproxy2_ip" "master1_ip" "master2_ip" "master3_ip" "worker1_ip" "worker2_ip")
    for vm_env_var in "${required_vms[@]}"; do
        if ! grep -q "^${vm_env_var} " vm-ips.env; then
            echo -e "${RED}Error: Required VM $vm_env_var not found in vm-ips.env.${NC}"
            check_failed=true
        else
            # Check if the IP is valid in the file
            ip=$(grep "^${vm_env_var} " vm-ips.env | cut -d \'\"\' -f 2)
            if [[ ! $ip =~ ^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$ ]]; then
                echo -e "${RED}Error: Invalid IP address found for $vm_env_var in vm-ips.env: $ip${NC}"
                check_failed=true
            fi
        fi
    done
    
    if [ "$check_failed" = true ]; then
         echo -e "${RED}VM creation process completed with errors. Failed VMs: ${failed_vms[*]}${NC}"
         echo -e "${RED}The vm-ips.env file may be incomplete or contain errors. Deployment might fail.${NC}"
         exit 1
    fi
    
    echo -e "${GREEN}All required VMs created successfully.${NC}"
    echo -e "${GREEN}VM IPs saved to vm-ips.env${NC}"
    echo -e "\\n${CYAN}VM IPs (in order of creation attempt):${NC}"
    # Display IPs in the order they were processed
    while IFS= read -r line; do 
        echo "$line" | sed 's/ = /: /g'
    done < vm-ips.env
}
# [END_LOCKED_FUNCTION] - Re-locking after modification notes

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
    
    cd "$PROJECT_DIR" || { echo -e "${RED}Error: Failed to change directory to $PROJECT_DIR${NC}"; exit 1; }
    
    # Run terraform init if needed (e.g., first run or backend changes)
    if [ ! -d ".terraform" ]; then
        echo -e "${CYAN}Running terraform init...${NC}"
        terraform init || { echo -e "${RED}Error: terraform init failed.${NC}"; exit 1; }
    else
        echo -e "${CYAN}Terraform already initialized. Skipping init.${NC}"
        # Consider running `terraform init -upgrade` periodically?
    fi

    # Run terraform plan first to check for errors and show the user
    echo -e "\\n${CYAN}Running terraform plan... Review the plan below:${NC}"
    terraform plan
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: terraform plan failed. Please check the errors above and resolve them before applying.${NC}"
        exit 1
    fi
    
    # Ask for confirmation before applying
    read -p "Do you want to apply these changes? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${CYAN}Aborting deployment.${NC}"
        exit 0
    fi

    # Run terraform apply (without auto-approve)
    echo -e "\\n${CYAN}Running terraform apply...${NC}"
    terraform apply 
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: terraform apply failed. Please check the errors above.${NC}"
        # Note: Terraform might be partially applied. Manual cleanup might be needed.
        exit 1
    fi
    
    echo -e "${GREEN}Kubernetes deployment completed successfully.${NC}"
    
    # Automatically update VM IPs after apply, as Terraform might configure static IPs or changes might occur.
    echo -e "\\n${CYAN}Updating VM IP information after Terraform apply...${NC}"
    update_vm_ips
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

    cd "$PROJECT_DIR" || { echo -e "${RED}Error: Failed to change directory to $PROJECT_DIR${NC}"; exit 1; }
    
    if [ ! -f "vm-ips.env" ]; then
        echo -e "${RED}Error: vm-ips.env not found. Run VM creation or IP update first.${NC}"
        return 1 # Use return code for functions called from menu
    fi

    # Load VM IPs from vm-ips.env safely
    declare -A vm_ips
    while IFS=' = ' read -r key value; do
        # Remove quotes from value if present
        value=$(echo $value | tr -d '"')
        # Map env var name (e.g., master1_ip) to a display name (e.g., Master1)
        local display_name=""
        case "$key" in
            haproxy1_ip) display_name="HAProxy1" ;;
            haproxy2_ip) display_name="HAProxy2" ;;
            master1_ip) display_name="Master1" ;;
            master2_ip) display_name="Master2" ;;
            master3_ip) display_name="Master3" ;;
            worker1_ip) display_name="Worker1" ;;
            worker2_ip) display_name="Worker2" ;;
            *) display_name=$(echo "$key" | sed 's/_ip$//') ;; # Basic fallback
        esac
        vm_ips["$display_name"]="$value"
    done < <(grep -E '^[a-zA-Z0-9_]+_ip\s*=\s*".+"$' vm-ips.env) # More robust parsing

    if [ ${#vm_ips[@]} -eq 0 ]; then
        echo -e "${RED}Error: No valid VM IPs found in vm-ips.env.${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Checking SSH connectivity to VMs defined in vm-ips.env:${NC}"
    local all_connected=true
    for name in "${!vm_ips[@]}"; do
        ip=${vm_ips[$name]}
        echo -n "Checking $name ($ip)... "
        # Use BatchMode=yes to prevent password prompts if key auth fails
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes ubuntu@$ip "echo -n 'OK'" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}Failed${NC}"
            all_connected=false
        fi
    done

    if [ "$all_connected" = true ]; then
        echo -e "${GREEN}Successfully connected to all VMs.${NC}"
        return 0
    else
        echo -e "${RED}Failed to connect to one or more VMs. Check VM status, IP addresses, and SSH configuration.${NC}"
        return 1
    fi
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
    if [ ! -f "$BASE_IMAGE_PATH" ]; then
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
    print_header "Creating Snapshots for all VMs"
    
    cd "$PROJECT_DIR" || { echo -e "${RED}Error: Failed to change directory to $PROJECT_DIR${NC}"; exit 1; }

    read -p "Enter a name for the snapshot: " snapshot_name
    if [ -z "$snapshot_name" ]; then
        echo -e "${RED}Snapshot name cannot be empty. Aborting.${NC}"
        return 1
    fi

    # Get list of VMX files for VMs in the cluster directory
    VMX_FILES=$(find "$VM_CLUSTER_DIR" -maxdepth 2 -name "*.vmx" -type f || true)

    if [ -z "$VMX_FILES" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return 1
    fi
    
    local all_success=true
    echo -e "${CYAN}Creating snapshot '$snapshot_name' for each VM...${NC}"
    for vmx_file in $VMX_FILES; do
        vm_name=$(basename "$(dirname "$vmx_file")" | sed 's/\\.vmwarevm//')
        echo -n "Creating snapshot for $vm_name... "
        if vmrun -T fusion snapshot "$vmx_file" "$snapshot_name"; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}Failed${NC}"
            all_success=false
        fi
    done

    if [ "$all_success" = true ]; then
        echo -e "${GREEN}Snapshots created successfully for all VMs.${NC}"
        return 0
    else
        echo -e "${RED}Failed to create snapshots for one or more VMs.${NC}"
        return 1
    fi
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
    print_header "Rollback VM to Snapshot"

    cd "$PROJECT_DIR" || { echo -e "${RED}Error: Failed to change directory to $PROJECT_DIR${NC}"; exit 1; }

    # Get list of VMX files
    VMX_FILES=($(find "$VM_CLUSTER_DIR" -maxdepth 2 -name "*.vmx" -type f || true))

    if [ ${#VMX_FILES[@]} -eq 0 ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return 1
    fi

    echo "Select VM to rollback:"
    select vmx_file in "${VMX_FILES[@]}"; do
        if [ -n "$vmx_file" ]; then
            break
        else
            echo "Invalid selection."
        fi
    done

    vm_name=$(basename "$(dirname "$vmx_file")" | sed 's/\\.vmwarevm//')
    echo -e "${CYAN}Selected VM: $vm_name${NC}"

    # List snapshots for the selected VM
    echo -e "\n${CYAN}Available snapshots for $vm_name:${NC}"
    snapshots=($(vmrun -T fusion listSnapshots "$vmx_file" | tail -n +2 || true)) # tail to skip header

    if [ ${#snapshots[@]} -eq 0 ]; then
        echo -e "${RED}No snapshots found for $vm_name.${NC}"
        return 1
    fi

    echo "Select snapshot to restore:"
    select snapshot_name in "${snapshots[@]}"; do
        if [ -n "$snapshot_name" ]; then
            break
        else
            echo "Invalid selection."
        fi
    done
    
    echo -e "${CYAN}Selected snapshot: $snapshot_name${NC}"
    
    # Confirm rollback
    read -p "Are you sure you want to rollback $vm_name to snapshot '$snapshot_name'? This cannot be undone. (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${CYAN}Rollback aborted.${NC}"
        return 1
    fi

    # Perform rollback
    echo -e "${CYAN}Rolling back $vm_name to snapshot '$snapshot_name'...${NC}"
    if vmrun -T fusion revertToSnapshot "$vmx_file" "$snapshot_name"; then
        echo -e "${GREEN}Successfully rolled back $vm_name to snapshot '$snapshot_name'.${NC}"
        # Optionally, start the VM after rollback?
        read -p "Do you want to start the VM $vm_name now? (yes/no): " start_confirm
        if [[ "$start_confirm" == "yes" ]]; then
            echo -e "${CYAN}Starting VM $vm_name...${NC}"
            vmrun -T fusion start "$vmx_file" || echo -e "${RED}Failed to start VM $vm_name.${NC}"
        fi
        # IPs might change after rollback, advise user
        echo -e "${CYAN}Note: The IP address of $vm_name might have changed. Run option 3 (Check VM status) to verify.${NC}"
        return 0
    else
        echo -e "${RED}Failed to rollback $vm_name to snapshot '$snapshot_name'.${NC}"
        return 1
    fi
}

# Delete a snapshot from all VMs
delete_all_snapshots() {
    print_header "Deleting All Snapshots"
    
    cd "$PROJECT_DIR" || { echo -e "${RED}Error: Failed to change directory to $PROJECT_DIR${NC}"; exit 1; }

    read -p "Are you sure you want to delete ALL snapshots for ALL VMs? This is irreversible. (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${CYAN}Deletion cancelled.${NC}"
        return 1
    fi

    # Get list of VMX files for VMs in the cluster directory
    VMX_FILES=$(find "$VM_CLUSTER_DIR" -maxdepth 2 -name "*.vmx" -type f || true)

    if [ -z "$VMX_FILES" ]; then
        echo -e "${RED}Error: No VMs found in $VM_CLUSTER_DIR${NC}"
        return 1
    fi
    
    local all_success=true
    echo -e "${CYAN}Deleting all snapshots for each VM...${NC}"
    for vmx_file in $VMX_FILES; do
        vm_name=$(basename "$(dirname "$vmx_file")" | sed \'s/\\.vmwarevm//\')
        echo -n "Deleting snapshots for $vm_name... "
        # Check if snapshots exist before attempting deletion
        if vmrun -T fusion listSnapshots "$vmx_file" | tail -n +2 | grep -q .; then
            if vmrun -T fusion deleteAllSnapshots "$vmx_file"; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${RED}Failed${NC}"
                all_success=false
            fi
        else
            echo -e "${CYAN}No snapshots found, skipping.${NC}"
        fi
    done

    if [ "$all_success" = true ]; then
        echo -e "${GREEN}All snapshots deleted successfully for all VMs.${NC}"
        return 0
    else
        echo -e "${RED}Failed to delete snapshots for one or more VMs.${NC}"
        return 1
    fi
}

# Function to delete all VMs
delete_all_vms() {
    print_header "Deleting All VMs and Related Files"

    cd "$PROJECT_DIR" || { echo -e "${RED}Error: Failed to change directory to $PROJECT_DIR${NC}"; exit 1; }

    read -p "Are you sure you want to delete all VMs and cleanup related files (vm-ips.env, generated/, terraform state)? This is irreversible. (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${CYAN}Deletion aborted.${NC}"
        return 1
    fi
    
    # Call the existing remove_existing_vms function which handles stopping and deleting
    remove_existing_vms
    
    echo -e "${GREEN}VM deletion and cleanup process completed.${NC}"
    return 0 # Assuming remove_existing_vms exits on error or succeeds
}

# Function for full deployment workflow
full_deployment_workflow() {
    print_header "Full Kubernetes Cluster Deployment Workflow"
    
    # Check prerequisites first
    check_prerequisites || exit 1 # Exit if prereqs fail
    
    # Warn user about potential data loss
    echo -e "${RED}Warning: This will remove any existing VMs in $VM_CLUSTER_DIR and deploy a new cluster.${NC}"
    read -p "Do you want to proceed? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo -e "${CYAN}Deployment aborted.${NC}"
        exit 0
    fi

    # Remove existing VMs
    remove_existing_vms

    # Download base image if needed
    download_base_image
    
    # Create VMs (now parallelized)
    create_vms || exit 1 # Exit if VM creation fails critically
    
    # Set up Terraform (this runs terraform-setup.sh)
    setup_terraform || exit 1 # Exit if setup fails

    # --- Add Snapshot Step --- 
    echo -e "\n${CYAN}VMs created and Terraform setup complete.${NC}"
    read -p "Do you want to create a snapshot of the clean VMs before deploying Kubernetes? (yes/no): " create_snap_confirm
    if [[ "$create_snap_confirm" == "yes" ]]; then
        create_snapshots || {
             echo -e "${RED}Snapshot creation failed. Halting deployment workflow.${NC}"
             # Exit the script if snapshot creation fails when requested
             exit 1
        }
    else
        echo -e "${CYAN}Skipping snapshot creation.${NC}"
    fi
    # --- End Snapshot Step ---

    # Deploy Kubernetes using Terraform
    deploy_kubernetes || exit 1 # Exit if deployment fails
    
    # Display cluster information
    display_cluster_info
    
    echo -e "${GREEN}Full deployment workflow completed successfully!${NC}"
}

# Main Menu
while true; do
    clear # Clear screen for better menu visibility
    echo -e "${BLUE}=========================================================${NC}"
    echo -e "${BLUE} Kubernetes Cluster Manager Menu ${NC}"
    echo -e "${BLUE} Project Dir: $PROJECT_DIR ${NC}"
    echo -e "${BLUE} VM Dir:      $VM_CLUSTER_DIR ${NC}"
    echo -e "${BLUE}=========================================================${NC}"
    echo "1.  Deploy Kubernetes Cluster (Full Workflow)"
    echo "2.  Create all VMs and basic configuration (Staggered Parallel)" # Updated menu text
    echo "3.  Check VM status and network configuration"
    echo "4.  Create snapshots of all VMs"
    echo "5.  List snapshots for all VMs"
    echo "6.  Rollback a VM to a snapshot"
    echo "7.  Delete all snapshots for all VMs"
    echo "8.  Delete all VMs and cleanup"
    echo "9.  Deploy Kubernetes on existing VMs (Terraform Apply)"
    echo "10. Update VM IPs file (vm-ips.env)"
    echo "11. Verify SSH connectivity to VMs"
    echo "0.  Exit"
    echo -e "${BLUE}=========================================================${NC}"

    read -p "Enter your choice [0-11]: " choice

    case $choice in
        1)
            full_deployment_workflow
            ;;
        2)
            print_header "Creating VMs and Basic Configuration (Staggered Parallel)" # Updated header
            # Check prerequisites first
            check_prerequisites || continue
            # Ask for confirmation as this is destructive
            echo -e "${RED}Warning: This will attempt to remove existing VMs in the cluster directory first.${NC}"
            read -p "Are you sure you want to create new VMs? (yes/no): " confirm_create
            if [[ "$confirm_create" == "yes" ]]; then
                remove_existing_vms
                download_base_image
                create_vms
            else
                echo -e "${CYAN}VM creation cancelled.${NC}"
            fi
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
            delete_all_vms
            ;;
        9)
            print_header "Deploying Kubernetes on Existing VMs"
            # Check prerequisites first
            check_prerequisites || continue
            # Ensure vm-ips.env exists and is populated
            if [ ! -f "vm-ips.env" ] || [ ! -s "vm-ips.env" ]; then
                 echo -e "${RED}Error: vm-ips.env is missing or empty. Run option 2 (Create VMs) or 10 (Update IPs) first.${NC}"
                 continue # Return to menu
            fi
            # Optionally run terraform setup if tfvars doesn't exist?
            if [ ! -f "terraform.tfvars" ]; then
                echo -e "${CYAN}terraform.tfvars not found. Running Terraform setup...${NC}"
                setup_terraform || continue # Return to menu if setup fails
            fi
            deploy_kubernetes
            # Don't display info here, deploy_kubernetes handles it and updates IPs
            # display_cluster_info 
            ;;
        10) 
            update_vm_ips 
            ;;
        11) 
            verify_connectivity 
            ;;
        0)
            echo -e "${GREEN}Exiting script.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice. Please try again.${NC}"
            ;;
    esac
    
    echo -e "\\n${CYAN}Press Enter to return to the menu...${NC}"
    read -r
done

# End of script
