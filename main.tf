# Control plane init node
resource "multipass_instance" "control_plane_init" {
  name           = "control-plane-1"
  image          = "22.04"
  cpus           = 4
  memory         = "4GiB"
  disk           = "20GiB"
  cloudinit_file = "control-plane-init.yaml"

  # Add a delay to allow cloud-init to complete
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# Additional control plane nodes
resource "multipass_instance" "control_plane_join" {
  count          = 2
  name           = "control-plane-${count.index + 2}"
  image          = "22.04"
  cpus           = 4
  memory         = "4GiB"
  disk           = "20GiB"
  cloudinit_file = "control-plane-join.yaml"

  depends_on = [multipass_instance.control_plane_init]

  # Add a delay between node creations
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# Worker nodes
resource "multipass_instance" "worker" {
  count          = 3
  name           = "worker-${count.index + 1}"
  image          = "22.04"
  cpus           = 2
  memory         = "3GiB"
  disk           = "20GiB"
  cloudinit_file = "worker-init.yaml"

  depends_on = [
    multipass_instance.control_plane_init,
    multipass_instance.control_plane_join[0],
    multipass_instance.control_plane_join[1]
  ]

  # Add a delay between worker creations
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# HAProxy load balancers
resource "multipass_instance" "haproxy" {
  count          = 2
  name           = "haproxy-${count.index + 1}"
  image          = "22.04"
  cpus           = 1
  memory         = "1GiB"
  disk           = "10GiB"
  cloudinit_file = "haproxy-init.yaml"

  # Add a delay between haproxy creations
  provisioner "local-exec" {
    command = "sleep 30"
  }
}

# Output the instance IPs for reference
output "control_plane_init_ip" {
  value = multipass_instance.control_plane_init.name
}

output "control_plane_join_ips" {
  value = [for instance in multipass_instance.control_plane_join : instance.name]
}

output "worker_ips" {
  value = [for instance in multipass_instance.worker : instance.name]
}

output "haproxy_ips" {
  value = [for instance in multipass_instance.haproxy : instance.name]
}

# Create a script to gather IPs instead of direct interpolation
resource "local_file" "get_ips_script" {
  filename = "get_cluster_ips.sh"
  content  = <<-EOT
    #!/bin/bash
    echo "Control Plane Init: $(multipass info control-plane-1 | grep IPv4 | awk '{print $2}')"
    echo "Control Plane Join: $(multipass info control-plane-2 | grep IPv4 | awk '{print $2}'), $(multipass info control-plane-3 | grep IPv4 | awk '{print $2}')"
    echo "Workers: $(multipass info worker-1 | grep IPv4 | awk '{print $2}'), $(multipass info worker-2 | grep IPv4 | awk '{print $2}'), $(multipass info worker-3 | grep IPv4 | awk '{print $2}')"
    echo "HAProxy: $(multipass info haproxy-1 | grep IPv4 | awk '{print $2}'), $(multipass info haproxy-2 | grep IPv4 | awk '{print $2}')"
  EOT
}

# Make the script executable
resource "null_resource" "make_script_executable" {
  depends_on = [local_file.get_ips_script]
  
  provisioner "local-exec" {
    command = "chmod +x get_cluster_ips.sh"
  }
}
