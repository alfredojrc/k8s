variable "control_plane_count" {
  description = "Number of control plane nodes"
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "haproxy_count" {
  description = "Number of HAProxy nodes"
  type        = number
  default     = 2
}

variable "k8s_version" {
  description = "Kubernetes version to install"
  type        = string
  default     = "1.29"
}

variable "pod_network_cidr" {
  description = "CIDR for pod network"
  type        = string
  default     = "192.168.0.0/16"
}

variable "virtual_ip" {
  description = "Virtual IP for HAProxy"
  type        = string
  default     = "172.16.0.100"
} 