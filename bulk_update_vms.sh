#!/usr/bin/env bash
set -e

# Check if K8S_APT_CACHE_SERVER_IP is set, otherwise load from file or default
if [ -z "$K8S_APT_CACHE_SERVER_IP" ]; then
    # Try to detect from running VM
    VMX_FILE="/Users/alf/VMs/apt_cache_vm/apt-cache-server.vmwarevm/apt-cache-server.vmx"
    if [ -f "$VMX_FILE" ]; then
        DETECTED_IP=$(vmrun -T fusion getGuestIPAddress "$VMX_FILE" -wait 2>/dev/null || echo "")
        if [[ $DETECTED_IP =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            export K8S_APT_CACHE_SERVER_IP="$DETECTED_IP"
            echo "Detected APT Cache Server IP: $K8S_APT_CACHE_SERVER_IP"
        fi
    fi
fi

# If still not set, warn
if [ -z "$K8S_APT_CACHE_SERVER_IP" ]; then
    echo "Warning: K8S_APT_CACHE_SERVER_IP is not set. Updates might be slow and consume internet bandwidth."
fi

# Load VM IPs from vm-ips.env
if [ ! -f "vm-ips.env" ]; then
    echo "Error: vm-ips.env not found. Run ./k8s-manager.sh -o 10 first."
    exit 1
fi

echo "--- Starting Bulk Update/Upgrade ---"

while IFS=' = ' read -r key value; do
    # Parse key and value
    vm_name=$(echo "$key" | sed 's/_ip//')
    vm_ip=$(echo "$value" | tr -d '"')
    
    echo -e "\n[ $vm_name ($vm_ip) ]"
    
    # 1. Configure APT Proxy (if IP is set)
    if [ -n "$K8S_APT_CACHE_SERVER_IP" ]; then
        echo "Configuring APT Proxy..."
        ssh -o StrictHostKeyChecking=no "ubuntu@$vm_ip" "echo 'Acquire::http::Proxy \"http://$K8S_APT_CACHE_SERVER_IP:3142\";' | sudo tee /etc/apt/apt.conf.d/01proxy"
    fi
    
    # 2. Update & Upgrade
    echo "Running apt-get update & upgrade..."
    # Running in background on remote or sequentially? Let's do sequential for safety but fast.
    # Suppress output for cleaner logs, or capture it.
    ssh -o StrictHostKeyChecking=no "ubuntu@$vm_ip" "sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y"
    
    echo "[ $vm_name ] Done."
    
done < <(grep "_ip" vm-ips.env)

echo -e "\n--- All VMs Updated ---"
