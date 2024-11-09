#!/bin/bash

echo "Stopping all Multipass instances..."
multipass stop --all

echo "Deleting all Multipass instances..."
multipass delete --all

echo "Purging deleted instances..."
multipass purge

echo "Cleaning up Terraform state..."
rm -f terraform.tfstate*
rm -f .terraform.lock.hcl
rm -rf .terraform/

echo "Cleanup complete. You can now run 'terraform init' and 'terraform apply'" 