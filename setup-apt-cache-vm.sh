#!/usr/bin/env bash
# Script to create and configure a dedicated apt-cacher-ng VM on VMware Fusion

set -e

# --- Configuration ---
# VM Settings
VM_NAME="apt-cache-server"
VM_MEMORY=2048 # 2GB RAM (adjust as needed)
VM_CPUS=2
VM_DISK_SIZE=60G # Adjust based on expected cache size

# Paths (Consider making these configurable via env vars if needed)
PROJECT_DIR="${K8S_PROJECT_DIR:-$HOME/godz/k8s}" # Use same base project dir for consistency
VM_BASE_DIR="${K8S_VM_BASE_DIR:-/Users/alf/VMs}" # Separate base directory for VMs recommended
VM_CACHE_DIR="$VM_BASE_DIR/apt_cache_vm" # Directory for this specific VM

BASE_IMAGE_PATH="${K8S_BASE_IMAGE_PATH:-$PROJECT_DIR/base_images/noble-server-cloudimg-arm64.img}"
BASE_IMAGE_URL="${K8S_BASE_IMAGE_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img}"
SSH_PUBLIC_KEY="${K8S_SSH_PUBLIC_KEY:-$HOME/.ssh/id_ed25519.pub}"
PASSWORD_FILE="${K8S_PASSWORD_FILE:-$HOME/.k8s_password}" # Reuse password for simplicity, or create a new one

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Helper Functions (Simplified from k8s-manager.sh) ---
print_header() {
    echo -e "\n${BLUE}=========================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================================${NC}"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_prerequisites() {
    print_header "Checking prerequisites"
    local error=0
    for cmd in vmrun qemu-img mkisofs curl openssl; do
        if ! command_exists $cmd; then
            echo -e "${RED}Error: Command '$cmd' not found. Please install it.${NC}"
            error=1
        fi
    done
    if [ ! -f "$SSH_PUBLIC_KEY" ]; then
         echo -e "${RED}Error: SSH Public Key not found at $SSH_PUBLIC_KEY${NC}"
         error=1
    fi
     if [ ! -f "$PASSWORD_FILE" ]; then
        echo -e "${CYAN}Password file ($PASSWORD_FILE) not found. Creating...${NC}"
        openssl rand -base64 12 > "$PASSWORD_FILE"
        chmod 600 "$PASSWORD_FILE"
        echo -e "${GREEN}Password file created.${NC}"
     else
        chmod 600 "$PASSWORD_FILE" # Ensure permissions
    fi
     # Check base image
     if [ ! -f "$BASE_IMAGE_PATH" ]; then
        echo -e "${CYAN}Base image not found at $BASE_IMAGE_PATH. Will attempt download.${NC}"
     fi
    [ $error -eq 1 ] && exit 1
    echo -e "${GREEN}Prerequisites seem OK.${NC}"
}

download_base_image_if_needed() {
    if [ ! -f "$BASE_IMAGE_PATH" ]; then
        print_header "Downloading Base Image"
        mkdir -p "$(dirname "$BASE_IMAGE_PATH")"
        echo -e "${CYAN}Downloading Ubuntu 24.04 LTS ARM64 cloud image...${NC}"
        curl -L "$BASE_IMAGE_URL" -o "$BASE_IMAGE_PATH" || { echo -e "${RED}Download failed!${NC}"; exit 1; }
        echo -e "${GREEN}Downloaded base image.${NC}"
    fi
}

create_vm_disk_local() {
    local vm_dir=$1
    local vm_name=$2
    local vm_disk_path="$vm_dir/$vm_name.vmdk"
    local tmp_qcow2="$vm_dir/temp_disk.qcow2"

    echo -e "${CYAN}Creating VM disk: $vm_disk_path (Size: $VM_DISK_SIZE)${NC}" >&2
    qemu-img convert -f raw -O qcow2 "$BASE_IMAGE_PATH" "$tmp_qcow2" || return 1
    qemu-img resize "$tmp_qcow2" "$VM_DISK_SIZE" || return 1
    qemu-img convert -f qcow2 -O vmdk "$tmp_qcow2" "$vm_disk_path" || return 1
    rm -f "$tmp_qcow2"
    echo -e "${GREEN}VM disk created.${NC}" >&2
}

create_cloud_init_iso_local() {
    local vm_dir=$1
    local vm_name=$2
    local password=$3
    local iso_path="$vm_dir/$vm_name-cloud-init.iso"

    echo -e "${CYAN}Creating cloud-init ISO: $iso_path${NC}" >&2

    # meta-data
    cat > "$vm_dir/meta-data" << EOF
instance-id: $vm_name
local-hostname: $vm_name
EOF

    # user-data (Install apt-cacher-ng)
    cat > "$vm_dir/user-data" << EOF
#cloud-config
hostname: $vm_name
fqdn: $vm_name.local
manage_etc_hosts: true
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    passwd: $(openssl passwd -6 "$password")
    ssh_authorized_keys:
      - $(cat "$SSH_PUBLIC_KEY")
package_update: true
package_upgrade: true
packages:
  - qemu-guest-agent
  - apt-cacher-ng # Install the caching server
runcmd:
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - echo "ubuntu:$password" | chpasswd
  - echo "PermitRootLogin no" >> /etc/ssh/sshd_config
  - echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
  - systemctl restart sshd
  # Enable and start apt-cacher-ng
  - systemctl enable apt-cacher-ng
  - systemctl start apt-cacher-ng
  - echo "APT Cache Server setup complete via cloud-init." > /etc/motd # Add a marker
power_state:
  mode: reboot
  timeout: 30
  condition: True
EOF

    # network-config (standard DHCP)
    cat > "$vm_dir/network-config" << EOF
version: 2
ethernets:
  ens160:
    dhcp4: true
    dhcp6: false
EOF

    mkisofs -output "$iso_path" -volid cidata -joliet -rock "$vm_dir/user-data" "$vm_dir/meta-data" "$vm_dir/network-config" || return 1
    rm -f "$vm_dir/user-data" "$vm_dir/meta-data" "$vm_dir/network-config" # Clean up temp files
    echo -e "${GREEN}Cloud-init ISO created.${NC}" >&2
}

create_vmx_file_local() {
    local vm_dir=$1
    local vm_name=$2
    local memory=$3
    local cpus=$4
    local vmx_path="$vm_dir/$vm_name.vmx"

    echo -e "${CYAN}Creating VMX file: $vmx_path${NC}" >&2
    cat > "$vmx_path" << EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
numvcpus = "$cpus"
memsize = "$memory"
displayName = "$vm_name"
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
nvme0:0.fileName = "$vm_name.vmdk"
sata0:1.present = "TRUE"
sata0:1.fileName = "$vm_name-cloud-init.iso"
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
    echo -e "${GREEN}VMX file created.${NC}" >&2
}

# --- Main Execution ---
check_prerequisites
download_base_image_if_needed

print_header "Creating APT Cache Server VM ($VM_NAME)"

VM_INSTANCE_DIR="$VM_CACHE_DIR/$VM_NAME.vmwarevm"
VMX_FILE="$VM_INSTANCE_DIR/$VM_NAME.vmx"

# Check if VM already exists
if [ -d "$VM_INSTANCE_DIR" ]; then
    echo -e "${CYAN}VM directory '$VM_INSTANCE_DIR' already exists.${NC}"
    if vmrun -T fusion list | grep -q -F "$VMX_FILE"; then
        echo -e "${CYAN}VM '$VM_NAME' is running.${NC}"
        read -p "Stop and delete the existing VM to recreate? (yes/no): " confirm_delete
    else
        echo -e "${CYAN}VM '$VM_NAME' exists but is not running.${NC}"
         read -p "Delete the existing VM files to recreate? (yes/no): " confirm_delete
    fi
    
    if [[ "$confirm_delete" != "yes" ]]; then
        echo -e "${CYAN}Exiting without changes. To manage the existing VM, use vmrun or VMware Fusion UI.${NC}"
        # Try to get IP if it exists and is running
        if vmrun -T fusion list | grep -q -F "$VMX_FILE"; then
             VM_IP=$(vmrun -T fusion getGuestIPAddress "$VMX_FILE" -wait 2>/dev/null || echo "")
             if [[ -n "$VM_IP" ]]; then
                 echo -e "
${GREEN}Existing APT Cache Server IP: $VM_IP${NC}"
                 echo -e "${CYAN}Use this IP for K8S_APT_CACHE_SERVER_IP environment variable.${NC}"
             fi
        fi
        exit 0
    fi

    # Stop if running
    if vmrun -T fusion list | grep -q -F "$VMX_FILE"; then
        echo -e "${CYAN}Stopping VM '$VM_NAME'...${NC}"
        vmrun -T fusion stop "$VMX_FILE" hard || echo -e "${RED}Warning: Failed to stop VM gracefully.${NC}"
        sleep 5
    fi
    # Delete directory
    echo -e "${CYAN}Deleting existing VM directory '$VM_INSTANCE_DIR'...${NC}"
    rm -rf "$VM_INSTANCE_DIR"
fi

# Create VM directory
echo -e "${CYAN}Creating VM directory: $VM_INSTANCE_DIR${NC}"
mkdir -p "$VM_INSTANCE_DIR"

# Load password
PASSWORD=$(cat "$PASSWORD_FILE")

# Create VM components
create_vm_disk_local "$VM_INSTANCE_DIR" "$VM_NAME" || { echo -e "${RED}Failed to create VM disk.${NC}"; exit 1; }
create_cloud_init_iso_local "$VM_INSTANCE_DIR" "$VM_NAME" "$PASSWORD" || { echo -e "${RED}Failed to create cloud-init ISO.${NC}"; exit 1; }
create_vmx_file_local "$VM_INSTANCE_DIR" "$VM_NAME" "$VM_MEMORY" "$VM_CPUS" || { echo -e "${RED}Failed to create VMX file.${NC}"; exit 1; }

# Start the VM
echo -e "${CYAN}Starting VM '$VM_NAME'...${NC}"
vmrun -T fusion start "$VMX_FILE" || { echo -e "${RED}Failed to start VM.${NC}"; exit 1; }

# Wait for IP
echo -e "${CYAN}Waiting for VM to boot and get IP address... (may take a minute or two)${NC}"
VM_IP=""
MAX_ATTEMPTS=30
ATTEMPT=0
while [ -z "$VM_IP" ] && [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT+1))
    VM_IP=$(vmrun -T fusion getGuestIPAddress "$VMX_FILE" -wait 2>/dev/null || echo "")
    if [[ $VM_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo -e "${GREEN}Got IP: $VM_IP${NC}"
        break
    else
        VM_IP=""
        echo -e "${CYAN}Waiting... ($ATTEMPT/$MAX_ATTEMPTS)${NC}"
        sleep 10
    fi
done

if [ -z "$VM_IP" ]; then
    echo -e "${RED}Failed to get IP address for APT Cache Server VM after $MAX_ATTEMPTS attempts.${NC}"
    echo -e "${RED}Check the VM console in VMware Fusion for errors.${NC}"
    exit 1
fi

# Final Output
print_header "APT Cache Server VM Created"
echo -e "${GREEN}VM Name: $VM_NAME${NC}"
echo -e "${GREEN}Status: Running${NC}"
echo -e "${GREEN}IP Address: $VM_IP${NC}"
echo -e "
${CYAN}To use this cache server for your Kubernetes VMs:${NC}"
echo -e "1. Set the environment variable before running k8s-manager.sh:"
echo -e "   ${GREEN}export K8S_APT_CACHE_SERVER_IP="$VM_IP"${NC}"
echo -e "2. Or, edit k8s-manager.sh and set the APT_CACHE_SERVER_IP variable directly."
echo -e "
${CYAN}The cache server address is: http://$VM_IP:3142${NC}"

exit 0 