terraform {
  required_providers {
    multipass = {
      source  = "larstobi/multipass"
      version = "~> 1.4.0"
    }
  }
}

provider "multipass" {}

resource "multipass_instance" "control_plane_init" {
  name           = "control-plane-1"
  image          = "24.04"
  cpus           = 4
  memory         = "4GiB"
  disk           = "20GiB"
  cloudinit_file = "control-plane-init.yaml"
}

resource "multipass_instance" "control_plane_join" {
  count          = 2
  name           = "control-plane-${count.index + 2}"
  image          = "24.04"
  cpus           = 4
  memory         = "4GiB"
  disk           = "20GiB"
  cloudinit_file = "control-plane-join.yaml"

  depends_on = [multipass_instance.control_plane_init]
}

resource "multipass_instance" "worker" {
  count          = 3
  name           = "worker-${count.index + 1}"
  image          = "24.04"
  cpus           = 2
  memory         = "3GiB"
  disk           = "20GiB"
  cloudinit_file = "worker-init.yaml"

  depends_on = [multipass_instance.control_plane_init, multipass_instance.control_plane_join[0], multipass_instance.control_plane_join[1]]
}

resource "multipass_instance" "haproxy" {
  name           = "haproxy"
  image          = "24.04"
  cpus           = 1
  memory         = "1GiB"
  disk           = "5GiB"
  cloudinit_file = "haproxy-init.yaml"

  depends_on = [multipass_instance.control_plane_init, multipass_instance.control_plane_join]
}
