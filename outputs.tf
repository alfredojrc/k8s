output "vm_ips" {
  description = "IP addresses of the VMs"
  value = {
    haproxy = "10.10.0.10"
    master  = "10.10.0.20"
    worker1 = "10.10.0.21"
    worker2 = "10.10.0.22"
  }
}

output "haproxy_ports" {
  description = "Ports exposed by HAProxy"
  value = {
    http  = "80"
    https = "443"
    stats = "8080"
  }
}

output "next_steps" {
  description = "Next steps after infrastructure creation"
  value = <<-EOT
    1. Initialize Kubernetes cluster on master node:
       limactl shell k8s-master sudo kubeadm init --pod-network-cidr=${var.pod_network_cidr} --service-cidr=${var.service_cidr}

    2. Choose and install ONE of the following network plugins:

       Option 1 - Flannel (Lightweight, basic networking):
       limactl shell k8s-master kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

       Option 2 - Calico (Advanced features like Network Policies, eBPF):
       limactl shell k8s-master kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

    3. Join worker nodes using the token from step 1

    4. Configure HAProxy:
       limactl shell haproxy sudo vim /etc/haproxy/haproxy.cfg

    Note: For most development environments, Flannel is sufficient. Choose Calico if you need:
    - Network Policies
    - eBPF support
    - Integrated Load Balancing
    - Ingress Controller
    - Gateway API support
  EOT
}

output "kubernetes_api_endpoint" {
  description = "Kubernetes API endpoint"
  value       = "${var.virtual_ip}:6443"
}

output "haproxy_nodes" {
  description = "HAProxy nodes information"
  value = [
    for node in local.haproxy_nodes : {
      name = node.name
      ip   = node.ip
    }
  ]
}

output "master_nodes" {
  description = "Kubernetes master nodes information"
  value = [
    for node in local.master_nodes : {
      name = node.name
      ip   = node.ip
    }
  ]
}

output "worker_nodes" {
  description = "Kubernetes worker nodes information"
  value = [
    for node in local.worker_nodes : {
      name = node.name
      ip   = node.ip
    }
  ]
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file on the first master node"
  value       = "/home/ubuntu/.kube/config"
}

output "virtual_ip" {
  description = "Virtual IP address for the HAProxy load balancer"
  value       = var.virtual_ip
} 