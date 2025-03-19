variable "haproxy_stats_credentials" {
  description = "Credentials for HAProxy stats page (format: username:password)"
  type        = string
  default     = "admin:admin"  # Change this in production
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+$", var.haproxy_stats_credentials))
    error_message = "Must be in username:password format without special characters"
  }
}

variable "haproxy_timeouts" {
  description = "HAProxy timeout settings in milliseconds"
  type        = map(number)
  default     = {
    connect = 5000
    client  = 50000
    server  = 50000
  }
}

variable "haproxy_maxconn" {
  description = "HAProxy maximum connections"
  type        = number
  default     = 2000
}

variable "base_image" {
  description = "Base image for VMs"
  type        = string
  default     = "ubuntu-24.04-base"  # Ubuntu 24.04 LTS (Noble Numbat)
}

variable "network_cidr" {
  description = "Network CIDR for the cluster"
  default     = "192.168.105.0/24"
}

variable "pod_network_cidr" {
  description = "CIDR for pod network"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "CIDR for Kubernetes services"
  type        = string
  default     = "10.96.0.0/12"
}

variable "disk_size" {
  description = "Disk size in MB"
  type        = map(number)
  default     = {
    haproxy = 20480    # 20GB
    master  = 30720    # 30GB
    worker  = 51200    # 50GB
  }
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
  default     = "~/.ssh/id_rsa.pub"  # Default SSH public key location
}

# Cilium Configuration
variable "cilium_version" {
  description = "Version of Cilium to install"
  type        = string
  default     = "1.16.0"  # Latest stable version
  
  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.cilium_version))
    error_message = "Cilium version must be in format X.Y.Z"
  }
}

variable "cilium_config" {
  description = "Cilium CNI configuration"
  type = object({
    enable_ipv4                  = bool
    enable_ipv6                  = bool
    enable_bpf_masquerade       = bool
    enable_host_reachable       = bool
    enable_bandwidth_manager    = bool
    enable_wireguard            = bool
    enable_hubble              = bool
    hubble_metrics             = list(string)
    kube_proxy_replacement     = string
    tunnel_protocol           = string
    ipam_mode                 = string
  })
  default = {
    enable_ipv4              = true
    enable_ipv6              = false
    enable_bpf_masquerade   = true
    enable_host_reachable   = true
    enable_bandwidth_manager = true
    enable_wireguard        = true
    enable_hubble          = true
    hubble_metrics         = ["dns","drop","tcp","flow","icmp","http"]
    kube_proxy_replacement = "strict"
    tunnel_protocol       = "disabled"
    ipam_mode            = "kubernetes"
  }

  validation {
    condition = contains(["strict", "probe", "partial", "disabled"], var.cilium_config.kube_proxy_replacement)
    error_message = "kube_proxy_replacement must be one of: strict, probe, partial, disabled"
  }

  validation {
    condition = contains(["disabled", "vxlan", "geneve"], var.cilium_config.tunnel_protocol)
    error_message = "tunnel_protocol must be one of: disabled, vxlan, geneve"
  }

  validation {
    condition = contains(["kubernetes", "cluster-pool", "azure"], var.cilium_config.ipam_mode)
    error_message = "ipam_mode must be one of: kubernetes, cluster-pool, azure"
  }

  validation {
    condition = alltrue([
      for metric in var.cilium_config.hubble_metrics :
      contains(["dns", "drop", "tcp", "flow", "icmp", "http", "port-distribution"], metric)
    ])
    error_message = "Invalid Hubble metrics specified. Allowed values: dns, drop, tcp, flow, icmp, http, port-distribution"
  }
}

variable "cilium_hubble_ui" {
  description = "Enable Hubble UI"
  type        = bool
  default     = true
}

variable "cilium_hubble_relay" {
  description = "Enable Hubble Relay"
  type        = bool
  default     = true
}

variable "kernel_parameters" {
  description = "Required kernel parameters for eBPF"
  type = map(string)
  default = {
    "net.core.bpf_jit_enable"          = "1"
    "net.ipv4.conf.all.rp_filter"      = "1"
    "net.ipv4.conf.default.rp_filter"  = "1"
    "net.ipv4.tcp_syncookies"          = "1"
    "kernel.kptr_restrict"             = "1"
    "kernel.dmesg_restrict"            = "1"
  }
}

variable "base_image_path" {
  description = "Path to base Lima image"
  type        = string
  default     = "~/godz/k8s/base_images/noble-server-cloudimg-arm64.img"
}

variable "secure_boot" {
  description = "Enable UEFI Secure Boot"
  type        = bool
  default     = false # Disabled until proper signing implemented
  
  validation {
    condition     = can(regex("^(true|false)$", tostring(var.secure_boot)))
    error_message = "Secure boot requires valid MOK keys"
  }
}

variable "master_ips" {
  description = "List of IP addresses for master nodes"
  type        = list(string)
  default     = ["192.168.105.20", "192.168.105.21", "192.168.105.22"]
}

variable "worker_ips" {
  description = "List of IP addresses for worker nodes"
  type        = list(string)
  default     = ["192.168.105.30", "192.168.105.31", "192.168.105.32"]
}

variable "haproxy1_ip" {
  description = "IP address of the first HAProxy VM"
  type        = string
  default     = ""
}

variable "haproxy2_ip" {
  description = "IP address of the second HAProxy VM"
  type        = string
  default     = ""
}

variable "master1_ip" {
  description = "IP address of the first Kubernetes master node"
  type        = string
  default     = ""
}

variable "master2_ip" {
  description = "IP address of the second Kubernetes master node"
  type        = string
  default     = ""
}

variable "master3_ip" {
  description = "IP address of the third Kubernetes master node"
  type        = string
  default     = ""
}

variable "worker1_ip" {
  description = "IP address of the first Kubernetes worker node"
  type        = string
  default     = ""
}

variable "worker2_ip" {
  description = "IP address of the second Kubernetes worker node"
  type        = string
  default     = ""
}

variable "virtual_ip" {
  description = "Virtual IP address for the HAProxy load balancer"
  type        = string
  default     = "10.10.0.100"
}

variable "network_interface" {
  description = "Network interface for keepalived"
  type        = string
  default     = "ens160"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key for connecting to VMs"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "ssh_username" {
  description = "Username for SSH connections to VMs"
  type        = string
  default     = "ubuntu"
}

variable "kubernetes_version" {
  description = "Kubernetes version to install"
  type        = string
  default     = "1.29.0"
} 