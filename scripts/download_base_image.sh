#!/bin/bash

# Script to download Ubuntu cloud image for VMware Fusion on Apple Silicon
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
UBUNTU_VERSION="24.04"
UBUNTU_CODENAME="noble"
IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-arm64.img"
IMAGE_PATH="./base_images"
IMAGE_NAME="noble-server-cloudimg-arm64.img"

echo -e "${YELLOW}Starting Ubuntu ${UBUNTU_VERSION} LTS (Noble Numbat) ARM64 base image download...${NC}"

# Create images directory if it doesn't exist
mkdir -p "${IMAGE_PATH}"

# Download the image if it doesn't exist
if [ ! -f "${IMAGE_PATH}/${IMAGE_NAME}" ]; then
    echo -e "${YELLOW}Downloading Ubuntu ${UBUNTU_VERSION} LTS ARM64 cloud image...${NC}"
    curl -L "${IMAGE_URL}" -o "${IMAGE_PATH}/${IMAGE_NAME}"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Successfully downloaded base image to ${IMAGE_PATH}/${IMAGE_NAME}${NC}"
    else
        echo -e "${RED}Failed to download base image${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}Base image already exists at ${IMAGE_PATH}/${IMAGE_NAME}${NC}"
fi

# Verify vmrun is available
if ! command -v vmrun &> /dev/null; then
    echo -e "${RED}vmrun not found. Please ensure VMware Fusion is installed and in your PATH.${NC}"
    echo -e "${YELLOW}You may need to add the following to your .zshrc or .bashrc:${NC}"
    echo -e "export PATH=\$PATH:\"/Applications/VMware Fusion.app/Contents/Public\""
    exit 1
fi

echo -e "${GREEN}Base image download completed successfully!${NC}"
echo -e "${YELLOW}You can now use this base image with the create-vms.sh script.${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Run ./create-vms.sh to create the VMs"
echo -e "2. Run ./terraform-setup.sh to set up Terraform"
echo -e "3. Run terraform apply to deploy Kubernetes" 