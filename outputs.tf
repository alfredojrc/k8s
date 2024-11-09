output "cluster_info" {
  description = "Cluster node information"
  value = {
    control_plane_init = multipass_instance.control_plane_init.name
    control_plane_join = [for instance in multipass_instance.control_plane_join : instance.name]
    workers           = [for instance in multipass_instance.worker : instance.name]
    haproxy           = [for instance in multipass_instance.haproxy : instance.name]
    virtual_ip        = var.virtual_ip
  }
}

output "kubeconfig_command" {
  description = "Command to copy kubeconfig"
  value = "multipass exec control-plane-1 -- sudo cat /etc/kubernetes/admin.conf > ~/.kube/config"
}

output "get_ips_command" {
  description = "Command to get cluster IPs"
  value = "./get_cluster_ips.sh"
} 