# Kubernetes Cluster Setup with Terraform and Multipass

This project sets up a production-grade Kubernetes cluster using Terraform and Multipass. It's designed to create a highly available Kubernetes environment suitable for learning, testing, and CKA (Certified Kubernetes Administrator) exam preparation.

## Project Structure

- `main.tf`: Main Terraform configuration for creating Multipass instances
- `variables.tf`: Variable definitions for the Terraform configuration
- `terraform.tfvars`: Default values for Terraform variables
- `versions.tf`: Required provider versions
- `outputs.tf`: Output definitions for cluster information
- `control-plane-init.yaml`: Cloud-init configuration for initializing the first control plane node
- `control-plane-join.yaml`: Cloud-init configuration for additional control plane nodes
- `worker-init.yaml`: Cloud-init configuration for worker nodes
- `haproxy-init.yaml`: Cloud-init configuration for HAProxy load balancers with Keepalived

## Cluster Configuration

- 3 Control Plane nodes (1 init + 2 join)
- 3 Worker nodes
- 2 HAProxy load balancers with Keepalived for high availability

### Node Specifications

- Control Plane nodes: 4 CPUs, 4GiB memory, 20GiB disk
- Worker nodes: 2 CPUs, 3GiB memory, 20GiB disk
- HAProxy nodes: 1 CPU, 1GiB memory, 5GiB disk

### Network Configuration
- Default Multipass bridge network (mpbr0)
- Virtual IP for HAProxy: 172.16.0.100
- Pod Network CIDR: 192.168.0.0/16
- Service CIDR: 10.96.0.0/12 (Kubernetes default)

### Terraform Configuration
The cluster can be customized using the following variables in `terraform.tfvars`:
```hcl
control_plane_count = 3    # Number of control plane nodes
worker_count       = 3     # Number of worker nodes
haproxy_count      = 2     # Number of HAProxy nodes
k8s_version        = "1.29" # Kubernetes version
pod_network_cidr   = "192.168.0.0/16"
virtual_ip         = "172.16.0.100"
```

## Key Features

### High Availability
- Dual HAProxy load balancers with Keepalived
- Virtual IP (192.168.64.100) for control plane access
- Automatic failover between HAProxy instances
- etcd backup and restore capabilities

### Networking
- Calico network plugin
- CoreDNS with optimized configuration
- Network policies for namespace isolation
- IPVS mode for kube-proxy

### Security
- Pod Security Standards
- Audit logging
- Resource quotas
- Network policies
- Secure communication between components

### Monitoring and Logging
- Prometheus and Grafana stack
- Metrics Server
- Comprehensive audit logging
- Log rotation for all components
- HAProxy logging and monitoring

### Backup and Recovery
- Automated etcd snapshots every 6 hours
- Backup retention management
- Disaster recovery procedures

### Additional Features
- Sample deployments and services
- CKA exam scenario setups
- Resource quotas and limits
- Cluster autoscaling configuration
- Node affinity rules for critical components

## Prerequisites

- Terraform >= 1.0.0
- Multipass >= 1.8.0
- Minimum system requirements:
  - 16GB RAM
  - 8 CPU cores
  - 100GB free disk space

## Installation

1. Clone this repository
```bash
git clone <repository-url>
cd kubernetes-multipass-cluster
```

2. (Optional) Modify terraform.tfvars to customize the cluster

3. Initialize Terraform
```bash
terraform init
```

4. Apply the configuration
```bash
terraform apply
```

5. Get cluster information
```bash
# View cluster information
cat cluster_info.txt

# Get kubeconfig
eval $(terraform output -raw kubeconfig_command)
```

## Access and Management

### Accessing the Cluster
The cluster can be accessed through the HAProxy virtual IP (172.16.0.100:6443)

### Kubeconfig Setup
```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Monitoring Access
- Grafana: http://<worker-node-ip>:30000 (Default credentials: admin/admin)
- Prometheus: http://<worker-node-ip>:30090

## Maintenance

### Backup Procedures
Automated etcd backups are configured to run every 6 hours. Backups are stored in:
```
/var/lib/etcd/backup/
```

### Log Locations
- Kubernetes audit logs: `/var/log/kubernetes/audit/audit.log`
- HAProxy logs: `/var/log/haproxy.log`
- System logs: `/var/log/syslog`

## Troubleshooting

### Common Issues
1. Node connectivity issues:
```bash
kubectl get nodes
kubectl describe node <node-name>
```

2. Pod networking issues:
```bash
kubectl get pods -A
kubectl describe pod <pod-name>
```

3. HAProxy status check:
```bash
systemctl status haproxy
systemctl status keepalived
```

### Log Collection
```bash
# Collect all relevant logs
kubectl cluster-info dump --output-directory=cluster-logs
```

### Network Troubleshooting
1. Check HAProxy and Keepalived status:
```bash
multipass exec haproxy-1 -- sudo systemctl status haproxy
multipass exec haproxy-1 -- sudo systemctl status keepalived
```

2. Verify virtual IP assignment:
```bash
multipass exec haproxy-1 -- ip addr show
```

3. Test control plane connectivity:
```bash
curl -k https://172.16.0.100:6443/healthz
```

### Terraform Troubleshooting
1. View Terraform outputs:
```bash
terraform output
```

2. Check instance status:
```bash
multipass list
```

3. Access instance logs:
```bash
multipass exec <instance-name> -- sudo cat /var/log/cloud-init-output.log
```

## Security Considerations

1. Network Policies are configured to:
   - Deny all ingress by default
   - Allow specific inter-namespace communication
   - Protect system namespaces

2. Pod Security Standards:
   - Restricted namespace configured
   - Pod Security Policy admission controller enabled

## Note

This setup includes production-grade features but should be further hardened for actual production use. Additional security measures and customizations may be needed based on specific requirements.

## Contributing

Contributions are welcome! Please read our contributing guidelines and submit pull requests.

## License

[MIT License](LICENSE)

