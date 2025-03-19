#!/bin/bash
# This script creates a VM with both SSH key authentication and a working password
# It handles all aspects of VM creation in a single script

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Configuration
VM_NAME="k8s-worker2"
VM_MEMORY=4096
VM_CPUS=4
VM_DISK_SIZE=40G
# [LOCKED_CONFIG: Do not change these base paths and methods]
BASE_IMAGE="$HOME/godz/k8s/base_images/noble-server-cloudimg-arm64.img"
VM_CLUSTER_DIR="$HOME/Virtual Machines.localized/k8s_cluster"
VM_DIR="$VM_CLUSTER_DIR/$VM_NAME.vmwarevm"
VM_DISK="$VM_DIR/$VM_NAME.vmdk"
VM_VMX="$VM_DIR/$VM_NAME.vmx"
CLOUD_INIT_ISO="$VM_DIR/$VM_NAME-cloud-init.iso"
SSH_PUBLIC_KEY="$HOME/.ssh/id_ed25519.pub"
# [END_LOCKED_CONFIG]

# Get password from password file or use a default if not available
PASSWORD_FILE="$HOME/.k8s_password"
if [ -f "$PASSWORD_FILE" ]; then
    PASSWORD="osNTdMa8GgKPQBy/"
else
    # Generate a random password if file doesn't exist
    PASSWORD="osNTdMa8GgKPQBy/"
    echo "$PASSWORD" > "$PASSWORD_FILE"
    chmod 600 "$PASSWORD_FILE"
fi

# Check if base image exists
if [ ! -f "$BASE_IMAGE" ]; then
    echo -e "${RED}Error: Base image not found at $BASE_IMAGE${NC}"
    exit 1
fi

# Check if SSH public key exists
if [ ! -f "$SSH_PUBLIC_KEY" ]; then
    echo -e "${RED}Error: SSH public key not found at $SSH_PUBLIC_KEY${NC}"
    exit 1
fi

echo "========================================================="
echo "Creating VM with SSH key and password authentication: $VM_NAME"
echo "Using base image: $BASE_IMAGE"
echo "========================================================="

# Delete existing VM if it exists
if vmrun -T fusion list | grep -q "${VM_VMX}"; then
    echo "Stopping existing VM..."
    vmrun -T fusion stop "${VM_VMX}" soft || true
    sleep 5
fi

if [ -d "$VM_DIR" ]; then
    echo "Deleting existing VM directory: $VM_DIR"
    rm -rf "$VM_DIR"
fi

# Create VM directory
echo "Creating VM directory: $VM_DIR"
mkdir -p "$VM_DIR"

# [LOCKED_DISK_CREATION: Do not modify the disk creation process]
# Create VM disk from base image - Using improved conversion process
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
# [END_LOCKED_DISK_CREATION]

# Create cloud-init configuration
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

# [LOCKED_VMX: Do not modify the VMX file structure]
# Create VMX file with settings matching template
echo -e "${YELLOW}Creating VMX file...${NC}"
cat > "$VM_VMX" << EOF
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
# [END_LOCKED_VMX]

# Start the VM
echo -e "${YELLOW}Starting VM...${NC}"
vmrun -T fusion start "$VM_VMX"

echo -e "${GREEN}VM $VM_NAME created successfully!${NC}"
echo -e "${YELLOW}Waiting for VM to boot and get an IP address...${NC}"
echo -e "${YELLOW}This may take a few minutes...${NC}"

# Wait for VM to boot and get IP address
VM_IP=$(vmrun -T fusion getGuestIPAddress "$VM_VMX" -wait)
echo -e "${GREEN}VM $VM_NAME IP address: $VM_IP${NC}"

# Print SSH command
echo -e "${YELLOW}You can SSH into the VM using:${NC}"
echo -e "ssh ubuntu@$VM_IP"
echo -e "${YELLOW}Password: $PASSWORD${NC}"

echo "========================================================="
echo "VM creation completed."
echo "========================================================="
echo "The VM has been configured with:"
echo "- Username: ubuntu"
echo "- Password: ${PASSWORD}"
echo "- SSH key authentication enabled"
echo "- SSH password authentication enabled"
echo "- Password expiration disabled"
echo ""
echo "You can SSH to the VM once it's booted with:"
echo "ssh ubuntu@<VM_IP>"
echo "or"
echo "ssh -o PreferredAuthentications=password ubuntu@<VM_IP>"
echo ""
echo "To get the VM's IP address, run:"
echo "vmrun -T fusion getGuestIPAddress \"${VM_VMX}\" -wait" 