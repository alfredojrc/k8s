#!/usr/bin/env bash
VM_CLUSTER_DIR="/Users/alf/VMs/k8s_cluster"
echo "Checking VM status in: $VM_CLUSTER_DIR"

VMWARE_VM_DIRS=$(find "$VM_CLUSTER_DIR" -maxdepth 1 -name "*.vmwarevm" -type d)

if [ -z "$VMWARE_VM_DIRS" ]; then
    echo "Error: No VMs found in $VM_CLUSTER_DIR"
    exit 1
fi

for VM_DIR in $VMWARE_VM_DIRS; do
    VM_NAME=$(basename "$VM_DIR" | sed 's/\.vmwarevm//')
    VMX_FILE="$VM_DIR/$VM_NAME.vmx"
    
    echo "---"
    echo "VM: $VM_NAME"
    
    if [ ! -f "$VMX_FILE" ]; then
        echo "Error: VMX file not found for $VM_NAME"
        continue
    fi
    
    if /Applications/VMware\ Fusion.app/Contents/Public/vmrun -T fusion list | grep -q "$VMX_FILE"; then
        VM_IP=$(/Applications/VMware\ Fusion.app/Contents/Public/vmrun -T fusion getGuestIPAddress "$VMX_FILE" 2>/dev/null || echo "Unknown")
        echo "Status: Running"
        echo "IP address: $VM_IP"
    else
        echo "Status: Not running"
    fi
done
