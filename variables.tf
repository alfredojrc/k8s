variable "gateway_stats_credentials" {
  description = "Credentials for Gateway (HAProxy) stats page (format: username:password)"
  type        = string
  default     = "admin:admin"  # Change this in production
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+$", var.gateway_stats_credentials))
    error_message = "Must be in username:password format without special characters"
  }
}

variable "gateway_timeouts" {
  description = "Gateway (HAProxy) timeout settings in milliseconds"
  type        = map(number)
  default     = {
    connect = 5000
    client  = 50000
    server  = 50000
  }
}

variable "gateway_maxconn" {
  description = "Gateway (HAProxy) maximum connections"
  type        = number
  default     = 2000
}

variable "pod_network_cidr" {
  description = "CIDR for pod network, used by Cilium and Kubeadm"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "CIDR for Kubernetes services"
  type        = string
  default     = "10.96.0.0/12"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access (used by cloud-init, less critical for Terraform itself if keys are pre-deployed)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"  # Aligning default with script expectation
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

variable "secure_boot" {
  description = "Enable UEFI Secure Boot"
  type        = bool
  default     = false # Disabled until proper signing implemented
  
  validation {
    condition     = can(regex("^(true|false)$", tostring(var.secure_boot)))
    error_message = "Secure boot requires valid MOK keys"
  }
}

variable "gateway1_ip" {
  description = "IP address of the first Gateway (HAProxy) VM (obtained from vm-ips.env)"
  type        = string
  default     = ""
}

variable "gateway2_ip" {
  description = "IP address of the second Gateway (HAProxy) VM (obtained from vm-ips.env)"
  type        = string
  default     = ""
}

variable "master1_ip" {
  description = "IP address of the first Kubernetes master node (obtained from vm-ips.env)"
  type        = string
  default     = ""
}

variable "master2_ip" {
  description = "IP address of the second Kubernetes master node (obtained from vm-ips.env)"
  type        = string
  default     = ""
}

variable "master3_ip" {
  description = "IP address of the third Kubernetes master node (obtained from vm-ips.env)"
  type        = string
  default     = ""
}

variable "worker1_ip" {
  description = "IP address of the first Kubernetes worker node (obtained from vm-ips.env)"
  type        = string
  default     = ""
}

variable "worker2_ip" {
  description = "IP address of the second Kubernetes worker node (obtained from vm-ips.env)"
  type        = string
  default     = ""
}

variable "virtual_ip" {
  description = "Virtual IP address for the Gateway load balancer (LAN-facing VIP)"
  type        = string
  default     = "192.168.68.200"  # External VIP on LAN for user access
  # Note: Internal K8s API endpoint uses 10.10.0.100 on vmnet2
}

variable "network_interface" {
  description = "Network interface for keepalived (Bridged LAN interface on Gateways)"
  type        = string
  default     = "ens160"  # Bridged interface for VIP on LAN (192.168.68.x)
  # Note: ens192 is the vmnet2 internal interface (10.10.0.x)
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key for connecting to VMs"
  type        = string
  default     = "~/.ssh/id_ed25519" # Aligning default with script expectation
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



variable "apt_proxy_url" {

  description = "URL of the APT proxy server (e.g., http://192.168.130.153:3142). Leave empty to disable."

  type        = string

  default     = ""

}

 