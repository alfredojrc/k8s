#!/usr/bin/env bash
# Script to configure a K8s VM (haproxy, master, worker) after initial boot

set -e
# Enable command tracing only if DEBUG is set
[ -n "$DEBUG" ] && set -x

# --- Configuration ---
# Optional APT Cache Server IP (leave empty to disable)
# Can be overridden by environment variable K8S_APT_CACHE_SERVER_IP
# Default is empty to allow direct internet access if not specified
APT_CACHE_SERVER_IP="${K8S_APT_CACHE_SERVER_IP:-}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}=========================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}=========================================================${NC}"
}

# --- Check Input ---
if [ -z "$1" ]; then
    echo -e "${RED}Usage: $0 <vm_ip_address>${NC}"
    exit 1
fi
VM_IP=$1

print_header "Configuring VM at $VM_IP"

# --- Check SSH Access ---
echo -e "${CYAN}Checking initial SSH connection...${NC}"
if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes ubuntu@"$VM_IP" "echo SSH OK"; then
    echo -e "${RED}Cannot SSH to $VM_IP as user ubuntu.${NC}"
    echo -e "Ensure VM is fully booted and accessible (check console password?)."
    exit 1
fi
echo -e "${GREEN}SSH connection successful.${NC}"

# --- Run Configuration Steps via SSH ---

setup_failed=false

# 1. Configure APT Proxy (if IP is set)
if [ -n "$APT_CACHE_SERVER_IP" ]; then
    echo -e "\n${CYAN}Ensuring APT config directory exists...${NC}"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$VM_IP" "sudo mkdir -p /etc/apt/apt.conf.d/" || {
        echo -e "${RED}Failed to create APT config directory!${NC}"; setup_failed=true;
    }
    
    if ! $setup_failed; then
        echo -e "\n${CYAN}Configuring APT proxy ($APT_CACHE_SERVER_IP)...${NC}"
        # Run tee without > /dev/null to see output/errors
        printf 'Acquire::http::Proxy "http://%s:3142";\n' "$APT_CACHE_SERVER_IP" | ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$VM_IP" "sudo tee /etc/apt/apt.conf.d/01proxy" || {
            echo -e "${RED}Failed to configure APT proxy!${NC}"; setup_failed=true; 
        }
        # Immediately verify file creation
        echo -e "\n${CYAN}Verifying proxy file creation...${NC}"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$VM_IP" "ls -l /etc/apt/apt.conf.d/01proxy" || {
             echo -e "${RED}Proxy file verification failed! (File likely not created)${NC}"; setup_failed=true;
        }
    fi
else
    echo -e "\n${CYAN}Skipping APT proxy configuration.${NC}"
fi

# 2. Run apt-get update
if ! $setup_failed; then
    echo -e "\n${CYAN}Running apt-get update...${NC}"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$VM_IP" "sudo apt-get update" || {
        echo -e "${RED}apt-get update failed!${NC}"; setup_failed=true; 
    }
fi

# 3. Install Required Packages
if ! $setup_failed; then
    echo -e "\n${CYAN}Installing required packages (open-vm-tools, qemu-guest-agent, etc.)...${NC}"
    # Using fixed package list from k8s-manager.sh
    PACKAGE_LIST="open-vm-tools qemu-guest-agent net-tools curl wget vim htop tmux bash-completion"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$VM_IP" "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $PACKAGE_LIST" || {
        echo -e "${RED}Package installation failed!${NC}"; setup_failed=true; 
    }
fi

# 4. Run apt-get upgrade
if ! $setup_failed; then
    echo -e "\n${CYAN}Running apt-get upgrade...${NC}"
     ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$VM_IP" "sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y" || {
        echo -e "${YELLOW}Warning: Package upgrade failed! Continuing...${NC}"; # Non-fatal
    }
fi

# 5. Enable/Start Services (qemu-guest-agent, vmtoolsd)
if ! $setup_failed; then
    echo -e "\n${CYAN}Ensuring services are enabled and running...${NC}"
    # Handle qemu-guest-agent separately and treat failure as warning
    echo "Attempting to enable/restart qemu-guest-agent (failure is non-critical)..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$VM_IP" "sudo systemctl enable qemu-guest-agent && sudo systemctl restart qemu-guest-agent" || echo -e "${YELLOW}Warning: qemu-guest-agent enable/restart failed. Continuing...${NC}"
    sleep 1
    
    # Handle vmtoolsd - failure IS critical
    echo "Attempting to enable/restart open-vm-tools.service..."
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$VM_IP" "sudo systemctl enable open-vm-tools.service && sudo systemctl restart open-vm-tools.service" || {
        echo -e "${RED}Failed to enable/restart open-vm-tools.service!${NC}"; setup_failed=true; 
    }
    
    if ! $setup_failed; then
        sleep 5 # Give service time to start
        # Verify vmtoolsd status independently using correct service name
        echo "Verifying open-vm-tools.service status..."
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$VM_IP" "systemctl is-active open-vm-tools.service" || {
            echo -e "${RED}open-vm-tools.service service is not active!${NC}"; setup_failed=true; 
        }
    fi
fi

# --- Final Result ---
if $setup_failed; then
     echo -e "\n${RED}VM configuration failed for $VM_IP. Please check errors above.${NC}"
     exit 1
else
    echo -e "\n${GREEN}VM configuration completed successfully for $VM_IP.${NC}"
    echo -e "${GREEN}VMWare Tools Status: $(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$VM_IP" "systemctl is-active open-vm-tools.service" 2>/dev/null || echo "Inactive/Error") ${NC}"
    echo -e "${GREEN}Proxy Config Exists: $(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ubuntu@"$VM_IP" "test -f /etc/apt/apt.conf.d/01proxy && echo Yes || echo No") ${NC}"
fi

exit 0 