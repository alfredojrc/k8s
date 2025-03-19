#!/bin/bash

# Script to clean up redundant files from the project
set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Cleaning up redundant files...${NC}"

# List of files to remove
FILES_TO_REMOVE=(
  # Redundant scripts
  "test-haproxy-config.sh"
  "VM_CREATION_README.md"
  
  # Redundant directories and their contents
  "fusion-configs/create-all-vms.sh"
  "fusion-configs/create-haproxy.sh"
  "fusion-configs/create-masters.sh"
  "fusion-configs/create-workers.sh"
  "fusion-configs/haproxy/haproxy.cfg"
  "fusion-configs/haproxy/haproxy.cfg.tftpl"
)

# Remove each file if it exists
for file in "${FILES_TO_REMOVE[@]}"; do
  if [ -e "$file" ]; then
    echo -e "${YELLOW}Removing $file...${NC}"
    rm -f "$file"
  else
    echo -e "${YELLOW}File $file does not exist, skipping...${NC}"
  fi
done

# Remove empty directories (macOS compatible)
echo -e "${YELLOW}Removing empty directories...${NC}"
if [ -d "fusion-configs/haproxy" ]; then
  # Check if directory is empty
  if [ -z "$(ls -A fusion-configs/haproxy)" ]; then
    echo -e "${YELLOW}Removing empty directory fusion-configs/haproxy...${NC}"
    rmdir "fusion-configs/haproxy"
  else
    echo -e "${YELLOW}Directory fusion-configs/haproxy is not empty, skipping...${NC}"
  fi
fi

if [ -d "fusion-configs" ]; then
  # Check if directory is empty
  if [ -z "$(ls -A fusion-configs)" ]; then
    echo -e "${YELLOW}Removing empty directory fusion-configs...${NC}"
    rmdir "fusion-configs"
  else
    echo -e "${YELLOW}Directory fusion-configs is not empty, skipping...${NC}"
  fi
fi

# Check if VMs directory is empty and remove it if it is
if [ -d "VMs" ] && [ -z "$(ls -A VMs)" ]; then
  echo -e "${YELLOW}Removing empty VMs directory...${NC}"
  rmdir "VMs"
fi

# Check if scripts directory is empty and remove it if it is
if [ -d "scripts" ] && [ -z "$(ls -A scripts)" ]; then
  echo -e "${YELLOW}Removing empty scripts directory...${NC}"
  rmdir "scripts"
else
  echo -e "${YELLOW}Keeping scripts directory as it contains useful scripts.${NC}"
fi

# Check if ovftool directory is needed
if [ -d "ovftool" ]; then
  echo -e "${YELLOW}The ovftool directory might be needed for VM creation. Do you want to keep it? (y/n)${NC}"
  read -p "Keep ovftool directory? " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}Removing ovftool directory...${NC}"
    rm -rf "ovftool"
  else
    echo -e "${GREEN}Keeping ovftool directory.${NC}"
  fi
fi

echo -e "${GREEN}Cleanup completed successfully!${NC}"
echo -e "${YELLOW}The following files and directories have been kept as they are essential:${NC}"
echo -e "- create-ubuntu-vm.sh: Script to create a single Ubuntu VM"
echo -e "- create-vms.sh: Script to create all VMs for the cluster"
echo -e "- terraform-setup.sh: Script to set up Terraform configuration"
echo -e "- main.tf, variables.tf, outputs.tf: Terraform configuration files"
echo -e "- templates/: Directory containing configuration templates"
echo -e "- generated/: Directory for generated configuration files"
echo -e "- base_images/: Directory for Ubuntu cloud images" 