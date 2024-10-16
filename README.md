# Kubernetes Cluster Setup with Terraform and Multipass

This project sets up a Kubernetes cluster using Terraform and Multipass. It's designed to create a multi-node Kubernetes environment suitable for learning and testing, particularly for CKA (Certified Kubernetes Administrator) exam preparation.

## Project Structure

- `main.tf`: Terraform configuration for creating Multipass instances
- `control-plane-init.yaml`: Cloud-init configuration for initializing the first control plane node
- `control-plane-join.yaml`: Cloud-init configuration for additional control plane nodes
- `worker-init.yaml`: Cloud-init configuration for worker nodes
- `haproxy-init.yaml`: Cloud-init configuration for HAProxy load balancer

## Cluster Configuration

- 3 Control Plane nodes (1 init + 2 join)
- 3 Worker nodes
- 1 HAProxy load balancer

### Node Specifications

- Control Plane nodes: 4 CPUs, 4GiB memory, 20GiB disk
- Worker nodes: 2 CPUs, 3GiB memory, 20GiB disk
- HAProxy: 1 CPU, 1GiB memory, 5GiB disk

## Kubernetes Version

This setup uses Kubernetes v1.31, which is aligned with the CKA exam requirements as of October 2024.

## Key Features

- Automated setup of a multi-node Kubernetes cluster
- HAProxy load balancing for control plane nodes
- Calico network plugin installation
- Metrics Server deployment
- Sample deployments and services for testing
- CKA exam scenario setups (ConfigMaps, Secrets, PV, PVC)

## Prerequisites

- Terraform installed
- Multipass installed
- Sufficient system resources to run the virtual machines

## Usage

1. Clone this repository
2. Navigate to the project directory
3. Run `terraform init` to initialize Terraform
4. Run `terraform apply` to create the cluster
5. To destroy the cluster, run `terraform destroy`

## Note

This setup is designed for learning and testing purposes, particularly for CKA exam preparation. It is not recommended for production use without further security considerations and optimizations.

## Troubleshooting

If you encounter issues with kubectl not being able to connect to the cluster, you may need to manually set up the kubeconfig file on the control plane node. SSH into the control plane node and run the following commands:
```zsh
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

This will create the .kube directory, copy the admin.conf file to it, and set the correct permissions. After running these commands, kubectl should be able to communicate with the cluster.

If you encounter other issues, check the cloud-init logs on the respective nodes:
multipass shell <node-name>
sudo cat /var/log/cloud-init-output.log

