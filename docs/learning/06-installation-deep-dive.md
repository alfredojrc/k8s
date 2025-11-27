# K8s HA Cluster Installation Deep Dive

**Created**: 2025-11-25
**Cluster**: k8s-vmware-lab (3 masters + 2 workers)
**Purpose**: CKA exam preparation with real-world deployment experience

---

## Table of Contents

1. [Phase 1: Infrastructure Layer](#phase-1-infrastructure-layer)
2. [Phase 2: OS Preparation](#phase-2-os-preparation)
3. [Phase 3: Container Runtime](#phase-3-container-runtime)
4. [Phase 4: K8s Package Installation](#phase-4-k8s-package-installation)
5. [Phase 5: Cluster Bootstrap](#phase-5-cluster-bootstrap-kubeadm-init)
6. [Phase 6: HA Control Plane](#phase-6-ha-control-plane-additional-masters)
7. [Phase 7: CNI Installation](#phase-7-cni-installation-cilium)
8. [Phase 8: Worker Nodes](#phase-8-worker-nodes-join)
9. [CKA Exam Failure Scenarios](#cka-exam-failure-scenarios)
10. [Troubleshooting Reference](#troubleshooting-reference)

---

## Phase 1: Infrastructure Layer

### Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Home LAN (192.168.68.0/24)                   │
│                              │                                   │
│                    ┌─────────┴─────────┐                        │
│                    │   VIP: .200       │                        │
│                    │   GW1: .201       │                        │
│                    │   GW2: .202       │                        │
│                    └─────────┬─────────┘                        │
└──────────────────────────────┼──────────────────────────────────┘
                               │ Bridged (ens160)
┌──────────────────────────────┼──────────────────────────────────┐
│                    vmnet2 (10.10.0.0/24)                        │
│                    NAT + Host-only                               │
│                              │                                   │
│    ┌─────────┬─────────┬─────┴─────┬─────────┬─────────┐       │
│    │         │         │           │         │         │       │
│  Master1  Master2  Master3     Worker1   Worker2   Gateway     │
│  .141     .142     .143        .144      .145      .146        │
└─────────────────────────────────────────────────────────────────┘
```

### VM Specifications

| VM | IP Address | vCPU | RAM | Disk | Role |
|----|------------|------|-----|------|------|
| k8s-master1 | 10.10.0.141 | 2 | 4GB | 50GB | Control Plane (init) |
| k8s-master2 | 10.10.0.142 | 2 | 4GB | 50GB | Control Plane |
| k8s-master3 | 10.10.0.143 | 2 | 4GB | 50GB | Control Plane |
| k8s-worker1 | 10.10.0.144 | 2 | 4GB | 50GB | Workload Node |
| k8s-worker2 | 10.10.0.145 | 2 | 4GB | 50GB | Workload Node |
| gateway1 | 10.10.0.146 / 192.168.68.201 | 1 | 1GB | 20GB | SSH Jump / LB |

### SSH Access Pattern

```bash
# Direct to gateway (from LAN)
ssh ubuntu@192.168.68.201

# Jump to internal nodes
ssh -J ubuntu@10.10.0.146 ubuntu@10.10.0.141  # master1
ssh -J ubuntu@10.10.0.146 ubuntu@10.10.0.144  # worker1

# SSH Key: ~/.ssh/id_ed25519 (Ed25519)
# User: ubuntu (passwordless sudo)
```

### What Can Fail (Infrastructure)

| Issue | Symptom | Fix |
|-------|---------|-----|
| VM not starting | vmrun error | Check VMX file, disk space |
| Wrong network adapter | No IP address | Verify vmnet2 in VMX |
| IP conflict | Intermittent connectivity | Check DHCP range, use static |
| Gateway unreachable | Can't SSH to internal nodes | Check bridged adapter |
| Firewall blocking | Connection refused | Open ports 6443, 2379-2380, 10250 |

### Required Ports

| Port | Protocol | Component | Direction |
|------|----------|-----------|-----------|
| 6443 | TCP | API Server | Inbound |
| 2379-2380 | TCP | etcd | Inbound (control plane) |
| 10250 | TCP | Kubelet API | Inbound |
| 10259 | TCP | Scheduler | Inbound (control plane) |
| 10257 | TCP | Controller Manager | Inbound (control plane) |
| 30000-32767 | TCP | NodePort Services | Inbound |

---

## Phase 2: OS Preparation

### Base Image
- **OS**: Ubuntu 24.04.3 LTS (Noble Numbat)
- **Kernel**: 6.8.0-86-generic
- **Architecture**: arm64 (Apple Silicon)

### cloud-init Configuration

File: `/templates/cloud-init-k8s.yaml`

```yaml
#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.local

users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_key}  # ~/.ssh/id_ed25519.pub content

write_files:
  # Network configuration (vmnet2 DHCP)
  - path: /etc/netplan/50-cloud-init.yaml
    content: |
      network:
        version: 2
        ethernets:
          ens160:
            dhcp4: true

  # Kernel modules for K8s
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

  # Sysctl parameters for K8s networking
  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1

package_update: true
package_upgrade: true

packages:
  - curl
  - vim
  - net-tools
  - containerd
  - apt-transport-https
  - ca-certificates
  - gnupg
```

### Kernel Module Loading

```bash
# Load modules immediately
sudo modprobe overlay
sudo modprobe br_netfilter

# Verify loaded
lsmod | grep -E "overlay|br_netfilter"

# Persistence: /etc/modules-load.d/k8s.conf
```

### Sysctl Parameters

```bash
# Apply immediately
sudo sysctl --system

# Verify
sysctl net.bridge.bridge-nf-call-iptables
sysctl net.ipv4.ip_forward

# Must show: = 1
```

### Swap Disabled

```bash
# Check swap status
free -h
swapon --show

# Disable temporarily
sudo swapoff -a

# Disable permanently (edit /etc/fstab)
sudo sed -i '/ swap / s/^/#/' /etc/fstab
```

### What Can Fail (OS Prep)

| Issue | Symptom | CKA Exam Fix |
|-------|---------|--------------|
| br_netfilter not loaded | CNI fails, pods can't communicate | `modprobe br_netfilter` |
| ip_forward=0 | Pods can't reach external network | `sysctl -w net.ipv4.ip_forward=1` |
| Swap enabled | kubeadm refuses to init | `swapoff -a` |
| Modules not persisted | Fails after reboot | Check `/etc/modules-load.d/` |

---

## Phase 3: Container Runtime

### containerd Configuration

```bash
# Generate default config
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml

# CRITICAL: Enable SystemdCgroup
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Restart containerd
sudo systemctl restart containerd
sudo systemctl enable containerd
```

### Verify containerd

```bash
# Check status
sudo systemctl status containerd

# Test with crictl
sudo crictl info

# Verify cgroup driver
grep SystemdCgroup /etc/containerd/config.toml
# Must show: SystemdCgroup = true
```

### Key Configuration File

Path: `/etc/containerd/config.toml`

Critical section:
```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  SystemdCgroup = true
```

### What Can Fail (Container Runtime)

| Issue | Symptom | CKA Exam Fix |
|-------|---------|--------------|
| SystemdCgroup = false | kubelet crashloop, cgroup mismatch | Edit config.toml, restart containerd |
| containerd not running | crictl: connection refused | `systemctl start containerd` |
| Socket permission | crictl: permission denied | Run as root or add user to group |

---

## Phase 4: K8s Package Installation

### Add Kubernetes Repository

```bash
# Create keyrings directory
sudo mkdir -p /etc/apt/keyrings

# Download GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update and install
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# Hold packages to prevent accidental upgrade
sudo apt-mark hold kubelet kubeadm kubectl
```

### Verify Installation

```bash
# Check versions
kubeadm version
kubelet --version
kubectl version --client

# All should show v1.32.x
```

### Package Versions Installed

| Package | Version | Purpose |
|---------|---------|---------|
| kubeadm | 1.32.10 | Cluster bootstrapper |
| kubelet | 1.32.10 | Node agent |
| kubectl | 1.32.10 | CLI tool |
| containerd | 1.7.28 | Container runtime |

### What Can Fail (Package Installation)

| Issue | Symptom | CKA Exam Fix |
|-------|---------|--------------|
| GPG key missing | apt-get update fails | Re-download key to keyrings |
| Repository not found | 404 error | Check URL, K8s version |
| Version mismatch | kubeadm init warns | Ensure all packages same version |
| Packages upgraded | Cluster version skew | `apt-mark hold` packages |

---

## Phase 5: Cluster Bootstrap (kubeadm init)

### Pre-flight Checks

```bash
# Run pre-flight only (no init)
sudo kubeadm init --dry-run

# Check required images
kubeadm config images list
```

### kubeadm init Command (First Master)

```bash
sudo kubeadm init \
  --control-plane-endpoint "10.10.0.141:6443" \
  --upload-certs \
  --pod-network-cidr=10.244.0.0/16 \
  --service-cidr=10.96.0.0/12 \
  --skip-phases=addon/kube-proxy  # For Cilium kube-proxy replacement
```

### Flag Explanation

| Flag | Value | Purpose |
|------|-------|---------|
| `--control-plane-endpoint` | 10.10.0.141:6443 | HA endpoint (use VIP in production) |
| `--upload-certs` | - | Upload certs to Secret for other masters |
| `--pod-network-cidr` | 10.244.0.0/16 | Pod IP range (CNI requirement) |
| `--service-cidr` | 10.96.0.0/12 | Service ClusterIP range |
| `--skip-phases=addon/kube-proxy` | - | Required for Cilium kube-proxy replacement |

### Output Tokens (SAVE THESE!)

```bash
# Worker join command (valid 24h)
kubeadm join 10.10.0.141:6443 \
  --token p0ykdh.vmz3xqtvg6j6rf1l \
  --discovery-token-ca-cert-hash sha256:90a6ecb90eb6c96c6294368795487b57b9ad1181f42dff06ced71284013e710f

# Control plane join (certificate-key valid 2h ONLY!)
kubeadm join 10.10.0.141:6443 \
  --token p0ykdh.vmz3xqtvg6j6rf1l \
  --discovery-token-ca-cert-hash sha256:90a6ecb90eb6c96c6294368795487b57b9ad1181f42dff06ced71284013e710f \
  --control-plane \
  --certificate-key c2056029ff595cfb59e20bdbb2fa02851c7f32a71ec3c2b36f7dc55c4d85a912
```

### Setup kubeconfig

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify
kubectl cluster-info
kubectl get nodes
```

### Certificates Generated

Location: `/etc/kubernetes/pki/`

| Certificate | Purpose | Validity |
|-------------|---------|----------|
| ca.crt/key | Cluster CA | 10 years |
| apiserver.crt/key | API Server TLS | 1 year |
| apiserver-kubelet-client.crt | API→Kubelet auth | 1 year |
| front-proxy-ca.crt/key | Front proxy CA | 10 years |
| etcd/ca.crt/key | etcd CA | 10 years |
| etcd/server.crt/key | etcd server TLS | 1 year |
| etcd/peer.crt/key | etcd peer TLS | 1 year |

### What Can Fail (kubeadm init)

| Issue | Symptom | CKA Exam Fix |
|-------|---------|--------------|
| Swap enabled | Pre-flight error | `swapoff -a` |
| Port 6443 in use | Bind error | Kill process, check for existing API server |
| Container runtime not ready | timeout error | `systemctl restart containerd` |
| Existing cluster files | Directory not empty | `kubeadm reset` first |
| Certificate-key expired | Can't join masters | `kubeadm init phase upload-certs --upload-certs` |

---

## Phase 6: HA Control Plane (Additional Masters)

### Join Command (master2, master3)

```bash
sudo kubeadm join 10.10.0.141:6443 \
  --token p0ykdh.vmz3xqtvg6j6rf1l \
  --discovery-token-ca-cert-hash sha256:90a6ecb90eb6c96c6294368795487b57b9ad1181f42dff06ced71284013e710f \
  --control-plane \
  --certificate-key c2056029ff595cfb59e20bdbb2fa02851c7f32a71ec3c2b36f7dc55c4d85a912
```

### Expected Transient Errors (NORMAL!)

These errors appear in logs during join and **resolve automatically**:

```
"node k8s-master2 not found"
  → Before node registration completes (30s)

"etcdserver: can only promote a learner member which is in sync with leader"
  → etcd syncing data before promotion (60s)

"etcd cluster is not healthy"
  → During etcd learner phase (60s)

"Container runtime network not ready"
  → Before CNI installation (resolve after Cilium)
```

### etcd Cluster Formation

```
Initial State (master1):
  └── etcd-master1 (Leader)

After master2 joins:
  ├── etcd-master1 (Leader)
  └── etcd-master2 (Learner → Voter)

After master3 joins:
  ├── etcd-master1 (Leader)
  ├── etcd-master2 (Voter)
  └── etcd-master3 (Learner → Voter)
```

### Verify HA Setup

```bash
# All masters should be Ready (after CNI)
kubectl get nodes

# etcd member list
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Control plane pods (3 of each)
kubectl get pods -n kube-system | grep -E "apiserver|scheduler|controller|etcd"
```

### What Can Fail (HA Join)

| Issue | Symptom | CKA Exam Fix |
|-------|---------|--------------|
| Certificate-key expired | "certificate-key invalid" | Re-upload: `kubeadm init phase upload-certs --upload-certs` |
| Token expired | "token invalid" | Create new: `kubeadm token create --print-join-command` |
| etcd quorum lost | API server unresponsive | Restore from backup or recreate |
| Network partition | Split brain | Fix network, possibly need to rejoin |

---

## Phase 7: CNI Installation (Cilium)

### CRITICAL: Installation Order

```
1. kubeadm init with --skip-phases=addon/kube-proxy
2. Install Gateway API CRDs (BEFORE Cilium!)
3. Install Cilium with kube-proxy replacement
```

### Gateway API CRDs (Required First)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml

# Verify
kubectl get crd | grep gateway
# Should show: gatewayclasses, gateways, httproutes, etc.
```

### Cilium Installation (Helm)

```bash
# Add Helm repo
helm repo add cilium https://helm.cilium.io/
helm repo update

# Install Cilium 1.18.4 with kube-proxy replacement
helm install cilium cilium/cilium --version 1.18.4 \
  --namespace kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=10.10.0.141 \
  --set k8sServicePort=6443 \
  --set gatewayAPI.enabled=true \
  --set l2announcements.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set ipam.mode=kubernetes
```

### Helm Flag Explanation

| Flag | Value | Purpose |
|------|-------|---------|
| `kubeProxyReplacement` | true | Replace kube-proxy entirely |
| `k8sServiceHost` | 10.10.0.141 | API server IP (Cilium needs this) |
| `k8sServicePort` | 6443 | API server port |
| `gatewayAPI.enabled` | true | Enable Gateway API support |
| `l2announcements.enabled` | true | L2 announcements for LoadBalancer |
| `hubble.relay.enabled` | true | Observability |
| `hubble.ui.enabled` | true | Hubble web UI |
| `ipam.mode` | kubernetes | Use K8s IPAM |

### Verify Cilium

```bash
# All Cilium pods should be Running
kubectl get pods -n kube-system -l app.kubernetes.io/name=cilium

# Cilium status
kubectl exec -n kube-system ds/cilium -- cilium status

# Nodes should now be Ready
kubectl get nodes
```

### What Can Fail (CNI)

| Issue | Symptom | CKA Exam Fix |
|-------|---------|--------------|
| Gateway API CRDs missing | Cilium Gateway features fail | Install CRDs first |
| kube-proxy conflict | Duplicate iptables rules | Ensure --skip-phases=addon/kube-proxy |
| Wrong API server IP | Cilium can't reach API | Check k8sServiceHost value |
| Nodes still NotReady | CNI not fully deployed | Wait for all Cilium pods Running |

---

## Phase 8: Worker Nodes Join

### Join Command (worker1, worker2)

```bash
sudo kubeadm join 10.10.0.141:6443 \
  --token p0ykdh.vmz3xqtvg6j6rf1l \
  --discovery-token-ca-cert-hash sha256:90a6ecb90eb6c96c6294368795487b57b9ad1181f42dff06ced71284013e710f
```

**Note**: No `--control-plane` flag for workers!

### Verify Workers

```bash
kubectl get nodes -o wide

# Should show:
# k8s-master1   Ready    control-plane
# k8s-master2   Ready    control-plane
# k8s-master3   Ready    control-plane
# k8s-worker1   Ready    <none>
# k8s-worker2   Ready    <none>
```

### What Can Fail (Worker Join)

| Issue | Symptom | CKA Exam Fix |
|-------|---------|--------------|
| Token expired | "token invalid" | `kubeadm token create --print-join-command` |
| Node NotReady | CNI issue | Check Cilium pods on worker |
| kubelet not starting | Node not appearing | `journalctl -u kubelet` |

---

## CKA Exam Failure Scenarios

### Scenario 1: Broken Static Pod

**Symptom**: kube-scheduler not running, pods stuck in Pending

**Break Method** (exam simulation):
```bash
# Corrupt scheduler manifest
sudo vim /etc/kubernetes/manifests/kube-scheduler.yaml
# Change image to invalid: k8s.gcr.io/kube-scheduler:BROKEN
```

**Fix**:
```bash
# Check static pod status
sudo crictl ps -a | grep scheduler

# View kubelet logs
sudo journalctl -u kubelet | grep scheduler

# Fix manifest
sudo vim /etc/kubernetes/manifests/kube-scheduler.yaml
# Correct the image tag to match K8s version

# kubelet automatically restarts static pod within 20 seconds
```

### Scenario 2: Expired Certificates

**Symptom**: `x509: certificate has expired` errors

**Check Expiration**:
```bash
kubeadm certs check-expiration
```

**Fix**:
```bash
# Renew all certificates
kubeadm certs renew all

# Restart control plane components
sudo systemctl restart kubelet

# Update kubeconfig
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### Scenario 3: kubelet Not Starting

**Symptom**: Node shows NotReady, kubelet.service failed

**Diagnosis**:
```bash
sudo systemctl status kubelet
sudo journalctl -u kubelet -f
```

**Common Causes & Fixes**:

| Cause | Log Message | Fix |
|-------|-------------|-----|
| Wrong CA path | "certificate signed by unknown authority" | Check kubelet.conf CA path |
| cgroupDriver mismatch | "cgroup driver mismatch" | Match containerd config |
| Swap enabled | "swap is enabled" | `swapoff -a` |
| Container runtime down | "connection refused" | `systemctl restart containerd` |

### Scenario 4: etcd Corruption/Unavailable

**Symptom**: API server unresponsive, "connection refused"

**Check etcd**:
```bash
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

**Restore from Backup**:
```bash
# Stop control plane
sudo mv /etc/kubernetes/manifests/*.yaml /tmp/

# Restore etcd
sudo ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restored

# Update etcd manifest to use new data-dir
sudo vim /tmp/etcd.yaml
# Change hostPath from /var/lib/etcd to /var/lib/etcd-restored

# Restart control plane
sudo mv /tmp/*.yaml /etc/kubernetes/manifests/
```

### Scenario 5: Service Not Routing to Pods

**Symptom**: Service exists but no response

**Diagnosis**:
```bash
# Check endpoints
kubectl get endpoints <service-name>

# If empty, check selector
kubectl get svc <service-name> -o yaml | grep -A5 selector
kubectl get pods --show-labels
```

**Fix**: Ensure service selector matches pod labels

### Scenario 6: DNS Not Resolving

**Symptom**: Pods can't resolve service names

**Diagnosis**:
```bash
# Test from pod
kubectl exec <pod> -- nslookup kubernetes.default

# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

**Fix**:
```bash
kubectl rollout restart deployment coredns -n kube-system
```

---

## Troubleshooting Reference

### Essential Commands

```bash
# Cluster status
kubectl cluster-info
kubectl get cs  # Component status (deprecated but may appear)
kubectl get nodes -o wide

# Pod debugging
kubectl describe pod <pod>
kubectl logs <pod> [-c container] [--previous]
kubectl exec -it <pod> -- /bin/sh

# Events
kubectl get events --sort-by='.lastTimestamp'

# Control plane logs
sudo journalctl -u kubelet -f
sudo crictl logs <container-id>

# Certificate check
kubeadm certs check-expiration

# etcd health
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

### File Locations

| Path | Purpose |
|------|---------|
| `/etc/kubernetes/manifests/` | Static pod manifests |
| `/etc/kubernetes/pki/` | Certificates |
| `/etc/kubernetes/admin.conf` | Admin kubeconfig |
| `/var/lib/kubelet/config.yaml` | Kubelet configuration |
| `/var/lib/etcd/` | etcd data directory |
| `/etc/containerd/config.toml` | containerd configuration |
| `/etc/cni/net.d/` | CNI configuration |

---

## Sources

- [Kubernetes Official Documentation](https://kubernetes.io/docs/)
- [kubeadm Troubleshooting](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/troubleshooting-kubeadm/)
- [Certificate Management with kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)
- [CKA Troubleshooting Guide](https://support.tools/training/cka-prep/08-troubleshooting/)
- [KodeKloud CKA Troubleshooting](https://kodekloud.com/blog/certified-kubernetes-administrator-exam-troubleshooting/)
- [etcd Troubleshooting for CKA 2025](https://medium.com/@farahjbara1/troubleshooting-etcd-a-guide-for-cka-exam-candidates-2025-1f10a65c632f)
