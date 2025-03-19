terraform {
  required_providers {
    null = {
      source = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "null" {}
provider "local" {}

# Load VM IPs from environment file
locals {
  vm_ips = {
    haproxy1 = var.haproxy1_ip != "" ? var.haproxy1_ip : try(trimspace(file("${path.module}/vm-ips.env")), "")
    haproxy2 = var.haproxy2_ip != "" ? var.haproxy2_ip : try(trimspace(file("${path.module}/vm-ips.env")), "")
    master1  = var.master1_ip != "" ? var.master1_ip : try(trimspace(file("${path.module}/vm-ips.env")), "")
    master2  = var.master2_ip != "" ? var.master2_ip : try(trimspace(file("${path.module}/vm-ips.env")), "")
    master3  = var.master3_ip != "" ? var.master3_ip : try(trimspace(file("${path.module}/vm-ips.env")), "")
    worker1  = var.worker1_ip != "" ? var.worker1_ip : try(trimspace(file("${path.module}/vm-ips.env")), "")
    worker2  = var.worker2_ip != "" ? var.worker2_ip : try(trimspace(file("${path.module}/vm-ips.env")), "")
  }

  # HAProxy configuration variables
  worker_nodes = [
    {
      name = "k8s-worker1"
      ip   = local.vm_ips.worker1
    },
    {
      name = "k8s-worker2"
      ip   = local.vm_ips.worker2
    }
  ]

  master_nodes = [
    {
      name = "k8s-master1"
      ip   = local.vm_ips.master1
    },
    {
      name = "k8s-master2"
      ip   = local.vm_ips.master2
    },
    {
      name = "k8s-master3"
      ip   = local.vm_ips.master3
    }
  ]
  
  haproxy_nodes = [
    {
      name     = "haproxy1"
      ip       = local.vm_ips.haproxy1
      priority = 101
    },
    {
      name     = "haproxy2"
      ip       = local.vm_ips.haproxy2
      priority = 100
    }
  ]
  
  # Kernel parameters for Kubernetes
  kernel_parameters = {
    "net.bridge.bridge-nf-call-iptables"  = "1"
    "net.bridge.bridge-nf-call-ip6tables" = "1"
    "net.ipv4.ip_forward"                 = "1"
  }
}

# Generate HAProxy configuration
resource "local_file" "haproxy_config" {
  content = templatefile("${path.module}/templates/haproxy.cfg.tpl", {
    master_nodes = local.master_nodes
    worker_nodes = local.worker_nodes
    stats_credentials = var.haproxy_stats_credentials
  })
  filename = "${path.module}/generated/haproxy.cfg"
}

# Generate keepalived configuration
resource "local_file" "keepalived_config" {
  count = length(local.haproxy_nodes)
  
  content = templatefile("${path.module}/templates/keepalived.conf.tpl", {
    priority      = local.haproxy_nodes[count.index].priority
    virtual_ip    = var.virtual_ip
    interface     = var.network_interface
    router_id     = 51
    auth_password = "k8s_vip_secret"
  })
  filename = "${path.module}/generated/keepalived_${local.haproxy_nodes[count.index].name}.conf"
}

# Configure HAProxy nodes
resource "null_resource" "configure_haproxy" {
  count = length(local.haproxy_nodes)
  
  triggers = {
    haproxy_config = local_file.haproxy_config.content_md5
    keepalived_config = local_file.keepalived_config[count.index].content_md5
  }
  
  # Install HAProxy and keepalived
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = local.haproxy_nodes[count.index].ip
      private_key = file(var.ssh_private_key_path)
    }
    
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y haproxy keepalived",
    ]
  }
  
  # Copy HAProxy configuration
  provisioner "file" {
    source      = local_file.haproxy_config.filename
    destination = "/tmp/haproxy.cfg"
    
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = local.haproxy_nodes[count.index].ip
      private_key = file(var.ssh_private_key_path)
    }
  }
  
  # Copy keepalived configuration
  provisioner "file" {
    source      = local_file.keepalived_config[count.index].filename
    destination = "/tmp/keepalived.conf"
    
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = local.haproxy_nodes[count.index].ip
      private_key = file(var.ssh_private_key_path)
    }
  }
  
  # Deploy configurations and restart services
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = local.haproxy_nodes[count.index].ip
      private_key = file(var.ssh_private_key_path)
    }
    
    inline = [
      "sudo haproxy -c -f /tmp/haproxy.cfg",
      "sudo cp /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg",
      "sudo rm -f /etc/keepalived/keepalived.conf",
      "sudo touch /etc/keepalived/keepalived.conf",
      "sudo chmod 644 /etc/keepalived/keepalived.conf",
      "cat /tmp/keepalived.conf | sudo tee /etc/keepalived/keepalived.conf > /dev/null",
      "sudo systemctl restart haproxy",
      "sudo systemctl restart keepalived",
      "sudo systemctl enable haproxy",
      "sudo systemctl enable keepalived",
    ]
  }
}

# Prepare Kubernetes nodes
resource "null_resource" "prepare_kubernetes_nodes" {
  count = length(local.master_nodes) + length(local.worker_nodes)
  
  triggers = {
    node_ip = count.index < length(local.master_nodes) ? local.master_nodes[count.index].ip : local.worker_nodes[count.index - length(local.master_nodes)].ip
  }
  
  # Install required packages
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = count.index < length(local.master_nodes) ? local.master_nodes[count.index].ip : local.worker_nodes[count.index - length(local.master_nodes)].ip
      private_key = file(var.ssh_private_key_path)
    }
    
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg",
      
      # Add Kubernetes apt repository
      "curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg",
      "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main' | sudo tee /etc/apt/sources.list.d/kubernetes.list",
      
      # Install containerd
      "sudo apt-get update",
      "sudo apt-get install -y containerd",
      
      # Configure containerd to use systemd cgroup driver
      "sudo mkdir -p /etc/containerd",
      "sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null",
      "sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml",
      "sudo systemctl restart containerd",
      
      # Disable swap
      "sudo swapoff -a",
      "sudo sed -i '/swap/d' /etc/fstab",
      
      # Configure kernel modules for Kubernetes
      "cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf\noverlay\nbr_netfilter\nEOF",
      "sudo modprobe overlay",
      "sudo modprobe br_netfilter",
      
      # Configure sysctl parameters for Kubernetes
      "cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf\nnet.bridge.bridge-nf-call-iptables  = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\nnet.ipv4.ip_forward                 = 1\nEOF",
      "sudo sysctl --system",
      
      # Install Kubernetes components
      "sudo apt-get update",
      "sudo apt-get install -y kubelet=${var.kubernetes_version}.* kubeadm=${var.kubernetes_version}.* kubectl=${var.kubernetes_version}.*",
      "sudo apt-mark hold kubelet kubeadm kubectl",
    ]
  }
}

# Initialize Kubernetes control plane
resource "null_resource" "initialize_kubernetes" {
  depends_on = [
    null_resource.configure_haproxy,
    null_resource.prepare_kubernetes_nodes
  ]
  
  # Create kubeadm configuration
  provisioner "local-exec" {
    command = <<-EOT
      cat > ${path.module}/generated/kubeadm-config.yaml << EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
nodeRegistration:
  name: k8s-master1
  criSocket: unix:///var/run/containerd/containerd.sock
localAPIEndpoint:
  advertiseAddress: ${local.master_nodes[0].ip}
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v${var.kubernetes_version}
controlPlaneEndpoint: "${var.virtual_ip}:6443"
networking:
  podSubnet: ${var.pod_network_cidr}
  serviceSubnet: ${var.service_cidr}
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF
    EOT
  }
  
  # Copy kubeadm configuration to the master node
  provisioner "file" {
    source      = "${path.module}/generated/kubeadm-config.yaml"
    destination = "/tmp/kubeadm-config.yaml"
    
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = local.master_nodes[0].ip
      private_key = file(var.ssh_private_key_path)
    }
  }
  
  # Initialize the control plane
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = local.master_nodes[0].ip
      private_key = file(var.ssh_private_key_path)
    }
    
    inline = [
      "sudo kubeadm init --config=/tmp/kubeadm-config.yaml --upload-certs | tee /tmp/kubeadm-init.log",
      "mkdir -p $HOME/.kube",
      "sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config",
      "sudo chown $(id -u):$(id -g) $HOME/.kube/config",
      "sudo kubeadm token create --print-join-command > /tmp/worker-join.sh",
      "sudo kubeadm init phase upload-certs --upload-certs | grep -A 1 'certificate key' | tail -n 1 > /tmp/cert-key.txt",
    ]
  }
  
  # Get join commands
  provisioner "local-exec" {
    command = <<-EOT
      scp -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} ubuntu@${local.master_nodes[0].ip}:/tmp/worker-join.sh ${path.module}/generated/worker-join.sh
      scp -o StrictHostKeyChecking=no -i ${var.ssh_private_key_path} ubuntu@${local.master_nodes[0].ip}:/tmp/cert-key.txt ${path.module}/generated/cert-key.txt
      CERT_KEY=$(cat ${path.module}/generated/cert-key.txt)
      WORKER_JOIN=$(cat ${path.module}/generated/worker-join.sh)
      echo "$WORKER_JOIN --control-plane --certificate-key $CERT_KEY" > ${path.module}/generated/master-join.sh
    EOT
  }
}

# Join additional master nodes
resource "null_resource" "join_master_nodes" {
  count = length(local.master_nodes) - 1
  
  depends_on = [null_resource.initialize_kubernetes]
  
  # Copy master join script
  provisioner "file" {
    source      = "${path.module}/generated/master-join.sh"
    destination = "/tmp/master-join.sh"
    
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = local.master_nodes[count.index + 1].ip
      private_key = file(var.ssh_private_key_path)
    }
  }
  
  # Join master node
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = local.master_nodes[count.index + 1].ip
      private_key = file(var.ssh_private_key_path)
    }
    
    inline = [
      "sudo bash /tmp/master-join.sh",
      "mkdir -p $HOME/.kube",
      "sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config",
      "sudo chown $(id -u):$(id -g) $HOME/.kube/config",
    ]
  }
}

# Install Cilium CNI
resource "null_resource" "install_cilium" {
  depends_on = [null_resource.join_master_nodes]
  
  # Install Cilium CLI
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = local.master_nodes[0].ip
      private_key = file(var.ssh_private_key_path)
    }
    
    inline = [
      "curl -L --remote-name-all https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-arm64.tar.gz{,.sha256sum}",
      "sha256sum --check cilium-linux-arm64.tar.gz.sha256sum",
      "sudo tar xzvf cilium-linux-arm64.tar.gz -C /usr/local/bin",
      "rm cilium-linux-arm64.tar.gz{,.sha256sum}",
      "cilium install --version ${var.cilium_version}",
      "cilium status --wait",
    ]
  }
}

# Join worker nodes
resource "null_resource" "join_worker_nodes" {
  count = length(local.worker_nodes)
  
  depends_on = [null_resource.install_cilium]
  
  # Copy worker join script
  provisioner "file" {
    source      = "${path.module}/generated/worker-join.sh"
    destination = "/tmp/worker-join.sh"
    
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = local.worker_nodes[count.index].ip
      private_key = file(var.ssh_private_key_path)
    }
  }
  
  # Join worker node
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = local.worker_nodes[count.index].ip
      private_key = file(var.ssh_private_key_path)
    }
    
    inline = [
      "sudo bash /tmp/worker-join.sh",
    ]
  }
}

# Verify cluster status
resource "null_resource" "verify_cluster" {
  depends_on = [
    null_resource.join_worker_nodes
  ]
  
  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = local.master_nodes[0].ip
      private_key = file(var.ssh_private_key_path)
    }
    
    inline = [
      "kubectl get nodes -o wide",
      "kubectl get pods -A -o wide",
    ]
  }
} 