#!/bin/bash
# This script validates the VM configurations to ensure they meet the requirements for VMware Fusion on Apple Silicon

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VM_CLUSTER_DIR="$HOME/Virtual Machines.localized/k8s_cluster"
BASE_IMAGE="$HOME/godz/k8s/base_images/noble-server-cloudimg-arm64.img"

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

# Check prerequisites
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
    
    echo -e "${GREEN}All prerequisites are met.${NC}"
}

# Validate base image
validate_base_image() {
    print_header "Validating base image"
    
    if [ ! -f "$BASE_IMAGE" ]; then
        echo -e "${RED}Error: Base image not found at $BASE_IMAGE${NC}"
        echo -e "${YELLOW}Please download the base image using the deploy-k8s-cluster.sh script.${NC}"
        exit 1
    fi
    
    # Check image format
    IMG_FORMAT=$(qemu-img info "$BASE_IMAGE" | grep "file format" | awk '{print $3}')
    
    if [ "$IMG_FORMAT" != "raw" ]; then
        echo -e "${RED}Error: Base image is not in RAW format. Found: $IMG_FORMAT${NC}"
        echo -e "${YELLOW}The base image should be in RAW format for proper conversion.${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Base image validation passed.${NC}"
}

# Validate script files
validate_scripts() {
    print_header "Validating script files"
    
    # Check if create-ubuntu-vm.sh exists and has correct settings
    if [ ! -f "./create-ubuntu-vm.sh" ]; then
        echo -e "${RED}Error: create-ubuntu-vm.sh not found${NC}"
        exit 1
    fi
    
    # Check for critical settings in create-ubuntu-vm.sh
    if ! grep -q "guestOS = \"arm-ubuntu-64\"" "./create-ubuntu-vm.sh"; then
        echo -e "${RED}Error: create-ubuntu-vm.sh does not use 'arm-ubuntu-64' as guestOS${NC}"
        echo -e "${YELLOW}This setting is critical for ARM64 VMs on Apple Silicon.${NC}"
        exit 1
    fi
    
    if ! grep -q "virtualHW.version = \"21\"" "./create-ubuntu-vm.sh"; then
        echo -e "${RED}Error: create-ubuntu-vm.sh does not use virtualHW.version = \"21\"${NC}"
        echo -e "${YELLOW}This setting is critical for ARM64 VMs on Apple Silicon.${NC}"
        exit 1
    fi
    
    if ! grep -q "nvme0.present = \"TRUE\"" "./create-ubuntu-vm.sh"; then
        echo -e "${RED}Error: create-ubuntu-vm.sh does not use nvme0.present = \"TRUE\"${NC}"
        echo -e "${YELLOW}The NVMe controller is required for ARM64 VMs on Apple Silicon.${NC}"
        exit 1
    fi
    
    if ! grep -q "ethernet0.virtualDev = \"e1000e\"" "./create-ubuntu-vm.sh"; then
        echo -e "${RED}Error: create-ubuntu-vm.sh does not use ethernet0.virtualDev = \"e1000e\"${NC}"
        echo -e "${YELLOW}The e1000e network adapter is required for ARM64 VMs on Apple Silicon.${NC}"
        exit 1
    fi
    
    # Check for proper disk creation process in create-ubuntu-vm.sh
    if ! grep -q "qemu-img convert -f raw -O qcow2" "./create-ubuntu-vm.sh"; then
        echo -e "${RED}Error: create-ubuntu-vm.sh does not use the correct disk conversion process${NC}"
        echo -e "${YELLOW}The proper conversion process should be: raw -> qcow2 -> vmdk${NC}"
        exit 1
    fi
    
    if ! grep -q "qemu-img convert -f qcow2 -O vmdk" "./create-ubuntu-vm.sh"; then
        echo -e "${RED}Error: create-ubuntu-vm.sh does not use the correct disk conversion process${NC}"
        echo -e "${YELLOW}The proper conversion process should be: raw -> qcow2 -> vmdk${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}Script validation passed.${NC}"
}

# Validate existing VMs if any
validate_existing_vms() {
    print_header "Validating existing VMs"
    
    if [ ! -d "$VM_CLUSTER_DIR" ]; then
        echo -e "${YELLOW}No VMs found. VM directory does not exist: $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    # Count existing VMs
    VM_COUNT=$(find "$VM_CLUSTER_DIR" -name "*.vmwarevm" -type d | wc -l)
    
    if [ "$VM_COUNT" -eq 0 ]; then
        echo -e "${YELLOW}No VMs found in $VM_CLUSTER_DIR${NC}"
        return
    fi
    
    echo -e "${GREEN}Found $VM_COUNT VMs in $VM_CLUSTER_DIR${NC}"
    
    # Check each VM
    VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -name "*.vmwarevm" -type d)
    
    for VM_DIR in $VMWARE_VM_DIRS; do
        VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
        VMX_FILE="$VM_DIR/$VM_NAME.vmx"
        
        echo -e "\n${YELLOW}Checking VM: $VM_NAME${NC}"
        
        if [ ! -f "$VMX_FILE" ]; then
            echo -e "${RED}Error: VMX file not found for $VM_NAME${NC}"
            continue
        fi
        
        # Check critical settings
        if ! grep -q "guestOS = \"arm-ubuntu-64\"" "$VMX_FILE"; then
            echo -e "${RED}Error: $VM_NAME does not use 'arm-ubuntu-64' as guestOS${NC}"
        else
            echo -e "${GREEN}[✓] guestOS correctly set to arm-ubuntu-64${NC}"
        fi
        
        if ! grep -q "virtualHW.version = \"21\"" "$VMX_FILE"; then
            echo -e "${RED}Error: $VM_NAME does not use virtualHW.version = \"21\"${NC}"
        else
            echo -e "${GREEN}[✓] virtualHW.version correctly set to 21${NC}"
        fi
        
        if ! grep -q "nvme0.present = \"TRUE\"" "$VMX_FILE"; then
            echo -e "${RED}Error: $VM_NAME does not use nvme0.present = \"TRUE\"${NC}"
        else
            echo -e "${GREEN}[✓] nvme0.present correctly set to TRUE${NC}"
        fi
        
        if ! grep -q "ethernet0.virtualDev = \"e1000e\"" "$VMX_FILE"; then
            echo -e "${RED}Error: $VM_NAME does not use ethernet0.virtualDev = \"e1000e\"${NC}"
        else
            echo -e "${GREEN}[✓] ethernet0.virtualDev correctly set to e1000e${NC}"
        fi
        
        if ! grep -q "firmware = \"efi\"" "$VMX_FILE"; then
            echo -e "${RED}Error: $VM_NAME does not use firmware = \"efi\"${NC}"
        else
            echo -e "${GREEN}[✓] firmware correctly set to efi${NC}"
        fi
        
        # Check if VM is running and get IP address if it is
        if vmrun -T fusion list | grep -q "$VMX_FILE"; then
            VM_IP=$(vmrun -T fusion getGuestIPAddress "$VMX_FILE" 2>/dev/null || echo "Unknown")
            echo -e "${GREEN}VM is running with IP address: $VM_IP${NC}"
        else
            echo -e "${YELLOW}VM is not running${NC}"
        fi
    done
}

# Run all validation checks
run_validation() {
    echo -e "${YELLOW}Running VM configuration validation...${NC}"
    check_prerequisites
    validate_base_image
    validate_scripts
    validate_existing_vms
    
    print_header "Validation Summary"
    echo -e "${GREEN}Validation completed.${NC}"
    echo -e "${YELLOW}If any errors were found, please fix them before proceeding with VM deployment.${NC}"
    echo -e "${YELLOW}Refer to ./docs/vm_deployment.md for detailed information about the VM deployment process.${NC}"
}

# Run the validation
run_validation 