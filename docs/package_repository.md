# Kubernetes Package Repository Documentation

## [LOCKED DOCUMENTATION: Do not modify the information in this section]

## Important Update (March 2024)

The Kubernetes package repositories underwent a significant change in 2023. This document captures critical information about these changes to ensure future deployments use the correct repositories.

### Package Repository Changes Timeline

- **August 15, 2023**: Kubernetes announced community-owned package repositories at `pkgs.k8s.io`
- **August 31, 2023**: Legacy Google-hosted repositories (`apt.kubernetes.io` and `yum.kubernetes.io`) were officially deprecated
- **September 13, 2023**: Legacy repositories were frozen (no new packages published after this date)
- **March 4, 2024**: Legacy Google-hosted repositories were completely removed

### New Repository Structure

The new community-owned repositories have a different structure than the legacy repositories:

1. Each Kubernetes minor version has its own dedicated repository URL
2. The URL format follows this pattern: `https://pkgs.k8s.io/core:/stable:/v1.XX.0/deb/` (for Debian/Ubuntu)
3. When upgrading to a new minor version, the repository URL must be updated

### Direct Installation Method

Due to potential issues with repository access (including 403 Forbidden errors), a direct installation method using binaries from `dl.k8s.io` is recommended:

```bash
# Download and install kubeadm, kubelet, and kubectl directly
ARCH=$(dpkg --print-architecture)
curl -LO https://dl.k8s.io/release/v1.29.0/bin/linux/$ARCH/kubelet
curl -LO https://dl.k8s.io/release/v1.29.0/bin/linux/$ARCH/kubeadm
curl -LO https://dl.k8s.io/release/v1.29.0/bin/linux/$ARCH/kubectl
sudo install -o root -g root -m 0755 kubectl kubeadm kubelet /usr/local/bin/
rm -f kubectl kubeadm kubelet

# Create necessary directories
sudo mkdir -p /etc/kubernetes/manifests
sudo mkdir -p /etc/systemd/system/kubelet.service.d
sudo mkdir -p /var/lib/kubelet
sudo mkdir -p /etc/cni/net.d
sudo mkdir -p /opt/cni/bin

# Create kubelet.service file
cat > /etc/systemd/system/kubelet.service << EOF
[Unit]
Description=kubelet: The Kubernetes Node Agent
Documentation=https://kubernetes.io/docs/home/
[Service]
ExecStart=/usr/local/bin/kubelet
Restart=always
StartLimitInterval=0
RestartSec=10
[Install]
WantedBy=multi-user.target
EOF

# Create kubelet.service.d/10-kubeadm.conf
cat > /etc/systemd/system/kubelet.service.d/10-kubeadm.conf << EOF
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
Environment="KUBELET_CGROUP_ARGS=--cgroup-driver=systemd"
Environment="KUBELET_SYSTEM_PODS_ARGS=--pod-manifest-path=/etc/kubernetes/manifests"
Environment="KUBELET_NETWORK_ARGS=--network-plugin=cni --cni-conf-dir=/etc/cni/net.d --cni-bin-dir=/opt/cni/bin"
Environment="KUBELET_DNS_ARGS=--cluster-dns=10.96.0.10 --cluster-domain=cluster.local"
Environment="KUBELET_AUTHZ_ARGS=--authorization-mode=Webhook --client-ca-file=/etc/kubernetes/pki/ca.crt"
Environment="KUBELET_EXTRA_ARGS="
ExecStart=
ExecStart=/usr/local/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_CGROUP_ARGS $KUBELET_SYSTEM_PODS_ARGS $KUBELET_NETWORK_ARGS $KUBELET_DNS_ARGS $KUBELET_AUTHZ_ARGS $KUBELET_EXTRA_ARGS
EOF

# Enable kubelet
sudo systemctl daemon-reload
sudo systemctl enable kubelet
```

### Known Issues

1. **403 Forbidden errors**: Some cloud providers block access to AWS IP addresses, which can cause 403 errors when accessing `pkgs.k8s.io`. The direct installation method avoids this issue.

2. **No file browser**: Unlike the legacy repositories, `pkgs.k8s.io` does not provide a file browser. Accessing URLs like `https://pkgs.k8s.io/core:/stable:/v1.29.0/deb/` directly will result in a 403 error. This is expected behavior.

3. **Repository signing**: The new repositories use a different signing method. Always follow the official Kubernetes documentation for repository setup.

## References

- [Official Announcement: pkgs.k8s.io Introduction](https://kubernetes.io/blog/2023/08/15/pkgs-k8s-io-introduction/)
- [Deprecation Announcement](https://kubernetes.io/blog/2023/08/31/legacy-package-repository-deprecation/)
- [Changing Package Repository Guide](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/change-package-repository/)
- [GitHub Issue: Error installing from official repos](https://github.com/kubernetes/release/issues/3219)

## [END LOCKED DOCUMENTATION] 