#!/bin/bash

echo "Setting up Multipass environment..."

# Stop and clean existing services
sudo snap stop multipass || true
sudo snap stop lxd || true

# Remove existing installations and clean up completely
sudo snap remove --purge multipass || true
sudo snap remove --purge lxd || true

# Clean up AppArmor profiles and cloud-init state
sudo rm -f /etc/apparmor.d/snap.multipass* || true
sudo rm -f /etc/apparmor.d/snap.lxd* || true
sudo rm -rf /var/lib/cloud/* || true
sudo systemctl reload apparmor

# Clean up any leftover mounts and network interfaces
sudo umount /run/user/1000/doc 2>/dev/null || true
sudo ip link delete mpbr0 2>/dev/null || true

# Install LXD
sudo snap install lxd

# Initialize LXD with specific profile and proper storage
cat <<EOF | sudo lxd init --preseed
config:
  core.https_address: '[::]:8443'
  core.trust_password: ubuntu
networks:
  - config:
      ipv4.address: auto
      ipv4.nat: true
      ipv6.address: none
    description: "Default LXD network bridge"
    name: lxdbr0
    type: bridge
storage_pools:
  - config:
      size: 15GB
    description: "Default storage pool"
    name: default
    driver: zfs
profiles:
  - config: {}
    description: "Default profile"
    devices:
      eth0:
        name: eth0
        network: lxdbr0
        type: nic
      root:
        path: /
        pool: default
        type: disk
    name: default
EOF

# Install Multipass
sudo snap install multipass

# Add current user to groups
sudo usermod -a -G lxd $USER
sudo usermod -a -G multipass $USER

# Configure AppArmor for Multipass with more permissive rules
sudo mkdir -p /etc/apparmor.d/local
cat << EOF | sudo tee /etc/apparmor.d/local/multipass.local
# Allow reading process maps and cloud-init operations
/proc/** r,
/var/lib/cloud/** rwk,
/run/cloud-init/** rwk,
# Allow network operations
network inet raw,
network inet6 raw,
# Allow system operations
/sys/fs/cgroup/** rwk,
/run/systemd/** rwk,
EOF

# Reload AppArmor profile
sudo apparmor_parser -r /etc/apparmor.d/snap.multipass.multipassd || true

# Connect required interfaces
sudo snap connect multipass:lxd lxd

# Configure Multipass to use LXD
sudo snap stop multipass
sudo multipass set local.driver=lxd
sudo snap start multipass

# Create required directories with proper permissions
sudo mkdir -p /var/lib/cloud/instance
sudo mkdir -p /run/cloud-init
sudo chmod -R 755 /var/lib/cloud
sudo chmod -R 755 /run/cloud-init
sudo chown -R root:root /var/lib/cloud
sudo chown -R root:root /run/cloud-init

# Wait for services to be ready
echo "Waiting for services to be ready..."
sleep 30

# Verify setup
echo "Verifying installation..."
multipass version
multipass list

# Check LXD status
echo "Checking LXD status..."
lxc list

# Show network configuration
echo "Network configuration:"
ip addr show

echo "Setup complete. You can now run 'terraform init' and 'terraform apply'"
echo "NOTE: Please log out and log back in for group changes to take effect"