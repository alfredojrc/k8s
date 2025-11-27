output "vm_ips" {
  description = "IP addresses of the VMs (vmnet2 - 10.10.0.0/24)"
  value = {
    # Gateway VMs have dual interfaces:
    #   - LAN (Bridged): 192.168.68.x for VIP
    #   - Internal (vmnet2): 10.10.0.x for cluster communication
    gateway1_lan      = "192.168.68.201"
    gateway1_internal = "10.10.0.146"
    gateway2_lan      = "192.168.68.202"
    gateway2_internal = "10.10.0.147"
    # K8s nodes on vmnet2 only (DHCP-assigned from vmnet2)
    master1  = "10.10.0.141"
    master2  = "10.10.0.142"
    master3  = "10.10.0.143"
    worker1  = "10.10.0.144"
    worker2  = "10.10.0.145"
  }
}

output "gateway_ports" {
  description = "Ports exposed by Gateway (HAProxy)"
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

    4. Configure Gateway (HAProxy):
       limactl shell gateway sudo vim /etc/haproxy/haproxy.cfg

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

output "gateway_nodes" {
  description = "Gateway (HAProxy) nodes information"
  value = [
    for node in local.gateway_nodes : {
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
  description = "Virtual IP address for the Gateway load balancer"
  value       = var.virtual_ip
} 