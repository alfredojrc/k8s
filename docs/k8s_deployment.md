# Kubernetes Deployment Documentation

## Overview

The k8s-manager.sh script provides powerful automation for deploying a highly available Kubernetes cluster on VMware Fusion VMs. This documentation covers the deployment process, configuration options, and post-deployment management.

## Table of Contents

1. [Deployment Architecture](#deployment-architecture)
2. [Deployment Methods](#deployment-methods)
3. [Configuration Options](#configuration-options)
4. [Deployment Process](#deployment-process)
5. [Post-Deployment Management](#post-deployment-management)
6. [Terraform Integration](#terraform-integration)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

## Deployment Architecture

The Kubernetes cluster deployed by this script follows a high-availability architecture:

```
                   ┌───────────┐     ┌───────────┐
                   │  haproxy1 │     │  haproxy2 │
                   └─────┬─────┘     └─────┬─────┘
                         │                 │
                         └────────┬────────┘
                                  │
                                  ▼
                 ┌─────────┬─────────┬─────────┐
                 │         │         │         │
           ┌─────┴───┐┌────┴────┐┌───┴─────┐   │
           │ master1 ││ master2 ││ master3 │   │
           └─────────┘└─────────┘└─────────┘   │
                 │         │         │         │
                 └─────────┴─────────┴─────────┘
                                  │
                         ┌────────┴────────┐
                         │                 │
                    ┌────┴─────┐     ┌─────┴────┐
                    │ worker1  │     │ worker2  │
                    └──────────┘     └──────────┘
```

Components:
- **Load Balancers**: Two HAProxy instances for high availability
- **Control Plane**: Three Kubernetes master nodes
- **Worker Nodes**: Two Kubernetes worker nodes
- **Virtual IP**: A floating IP address for accessing the Kubernetes API

## Deployment Methods

The script offers two primary methods for deploying Kubernetes:

### 1. Full Workflow Deployment

This option creates VMs and deploys Kubernetes in a single workflow:

1. From the main menu, select option 1: "Deploy Kubernetes Cluster (Full Workflow)"
2. The script will:
   - Remove any existing VMs
   - Download the base image if needed
   - Create all the VMs
   - Verify VM connectivity
   - Set up Terraform
   - Deploy Kubernetes
   - Display cluster information

### 2. Deployment on Existing VMs

This option allows you to deploy Kubernetes on VMs you've already created:

1. From the main menu, select option 6: "Deploy Kubernetes on existing VMs"
2. The script will:
   - Check for the vm-ips.env file
   - Set up Terraform
   - Deploy Kubernetes
   - Display cluster information

## Configuration Options

While most configuration options are set with sensible defaults, you can modify:

- VM resource allocation (before VM creation)
- Kubernetes version (in Terraform variables)
- Network settings (in Terraform variables)
- Pod and service CIDR (in Terraform variables)

## Deployment Process

The Kubernetes deployment process involves these major steps:

### 1. Infrastructure Preparation

- Creating the necessary VMs
- Setting up HAProxy load balancers
- Configuring networking between components

### 2. Terraform Setup

The script runs `terraform-setup.sh` which:
- Creates terraform.tfvars file from vm-ips.env
- Configures variables for deployment

### 3. Kubernetes Deployment

The script uses Terraform to:
- Configure HAProxy for Kubernetes API load balancing
- Install Kubernetes components on master nodes
- Initialize the Kubernetes cluster on the first master
- Join additional masters to the cluster
- Join worker nodes to the cluster
- Deploy networking components

### 4. Post-Deployment Configuration

- Set up kubectl access
- Configure cluster networking
- Apply security policies

## Post-Deployment Management

After deployment, you can:

1. **Access the cluster**: SSH to the first master node and use kubectl
2. **Monitor the deployment**: Check the HAProxy stats page
3. **Deploy applications**: Use kubectl to deploy workloads

## Terraform Integration

The script integrates with Terraform for infrastructure management:

- **Terraform Files**: Located in the project directory
- **State Files**: Generated during deployment
- **Variables**: Configured automatically from VM IPs

Key Terraform resources deployed:
- HAProxy configuration
- Keepalived for virtual IP
- Kubernetes cluster components
- Network configuration

## Best Practices

1. **Pre-Deployment**:
   - Take snapshots of VMs before deployment
   - Ensure all VMs are running
   - Update VM IP addresses

2. **Deployment**:
   - Use the full workflow for a clean deployment
   - Monitor the deployment process for errors
   - Allow time for all components to initialize

3. **Post-Deployment**:
   - Take snapshots of working deployments
   - Test cluster functionality
   - Follow standard Kubernetes best practices

4. **Updates**:
   - Take snapshots before updating
   - Update one component at a time
   - Test thoroughly after updates

## Troubleshooting

### Common Issues and Solutions

1. **Terraform Apply Fails**
   - Check VM connectivity
   - Verify vm-ips.env is correct
   - Check for errors in Terraform logs

2. **Kubernetes API Not Accessible**
   - Verify HAProxy configuration
   - Check master node status
   - Verify network connectivity

3. **Nodes Not Joining**
   - Check join token and certificates
   - Verify network connectivity
   - Check kubelet logs on nodes

4. **Network Issues**
   - Verify pod network CIDR
   - Check CNI plugin deployment
   - Verify VM network configuration

### Recovery Options

1. **Rolling Back**:
   - Use snapshot management to restore VMs to a previous state
   - Run the full workflow again
   - Run only the Kubernetes deployment on existing VMs

2. **Manual Intervention**:
   - SSH into VMs to check logs
   - Manually fix issues
   - Resume automation 