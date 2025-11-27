# Security Best Practices

**Last Updated**: 2025-03-19
**Status**: Production Guidance

---

## Table of Contents

1. [Secret Management](#secret-management)
2. [Git Security](#git-security)
3. [Credential Rotation](#credential-rotation)
4. [Access Control](#access-control)
5. [Network Security](#network-security)
6. [Incident Response](#incident-response)

---

## Secret Management

### Overview

This project uses **environment variables** for secret management, following the [12-factor app methodology](https://12factor.net/config).

### File Structure

```
.env.example       # Template (safe to commit)
.env               # Real secrets (NEVER commit)
.gitignore         # Excludes .env* patterns
setup-env.sh       # Generates secure random passwords
```

### Setup Process

**Initial Setup**:
```bash
# 1. Generate .env with secure random passwords
./setup-env.sh

# 2. Review and customize (optional)
cat .env

# 3. Export for current shell session
export $(grep -v '^#' .env | xargs)

# 4. Verify variables loaded
echo $KEEPALIVED_AUTH_PASSWORD
```

**Terraform Integration**:
```bash
# Method 1: Export to environment (recommended)
export $(grep -v '^#' .env | xargs)
terraform apply

# Method 2: Pass as CLI variables
terraform apply \
  -var="keepalived_auth_password=${KEEPALIVED_AUTH_PASSWORD}" \
  -var="gateway_stats_credentials=${GATEWAY_STATS_CREDENTIALS}"

# Method 3: Use .tfvars (less secure, can be committed accidentally)
# NOT RECOMMENDED
```

### Secrets Inventory

| Secret | Purpose | Max Length | Format |
|--------|---------|------------|--------|
| `KEEPALIVED_AUTH_PASSWORD` | VRRP failover authentication | 8 chars | Alphanumeric |
| `GATEWAY_STATS_CREDENTIALS` | HAProxy/Nginx monitoring | - | username:password |
| `QDRANT_API_KEY` | Vector database API access | 32 chars | Hex string |

### Storage Best Practices

**✅ DO**:
- Use `.env` files (gitignored)
- Store in password managers (1Password, LastPass, Bitwarden)
- Use environment variables in CI/CD (GitHub Secrets, GitLab CI/CD variables)
- Set restrictive file permissions: `chmod 600 .env`
- Rotate regularly (every 90 days minimum)

**❌ DON'T**:
- Commit secrets to git (even private repos)
- Store in shell history (use `export` not `EXPORT VAR=secret`)
- Share via Slack/email/messaging
- Hardcode in application code
- Use default passwords in production

---

## Git Security

### Preventing Secret Leaks

**Pre-commit Checks**:
```bash
# Install git-secrets (Homebrew)
brew install git-secrets

# Initialize for this repo
cd /Users/alf/godz/k8s
git secrets --install
git secrets --register-aws

# Add custom patterns
git secrets --add 'KEEPALIVED_AUTH_PASSWORD=[a-zA-Z0-9]+'
git secrets --add 'QDRANT_API_KEY=[a-f0-9]{32}'
git secrets --add 'password["\s]*[:=]["\s]*[^"]+'

# Test (should fail with secrets)
git secrets --scan
```

**GitGuardian Integration** (Current Issue):
- GitGuardian detected leaked password in commits `f584a5e` and `43d9089`
- Issue: `auth_password = "k8s_vip_secret"` in `main.tf:95` (now fixed)

### Cleaning Git History

**⚠️ WARNING**: Rewriting history affects all collaborators. Coordinate before executing.

**Option 1: BFG Repo-Cleaner** (Recommended):
```bash
# Install BFG
brew install bfg

# Backup repo
cd /Users/alf/godz/k8s
git clone --mirror . ../k8s-backup.git

# Create patterns file
cat > secrets-to-remove.txt << 'EOF'
k8s_vip_secret
admin:admin
QDRANT_API_KEY=.*
EOF

# Remove secrets
bfg --replace-text secrets-to-remove.txt

# Clean up
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# Force push (DESTRUCTIVE)
git push --force
```

**Option 2: git-filter-repo**:
```bash
# Install git-filter-repo
brew install git-filter-repo

# Backup first
git clone . ../k8s-backup

# Remove specific file from history
git filter-repo --path main.tf --invert-paths

# Or remove specific text
git filter-repo --replace-text secrets-to-remove.txt

# Force push
git push --force
```

**Option 3: GitHub Secret Scanning** (if public repo):
- GitHub will automatically detect and alert on secrets
- Navigate to: Settings → Security → Secret scanning alerts
- Resolve by rotating credentials + cleaning history

### Post-Cleanup Actions

1. **Notify all collaborators**: History rewritten, re-clone required
2. **Rotate all exposed credentials**: `./setup-env.sh` (overwrite)
3. **Update CI/CD secrets**: GitHub Actions, GitLab CI, etc.
4. **Monitor for unauthorized access**: Check logs for gateway/Qdrant access
5. **Update documentation**: Record incident in this file

---

## Credential Rotation

### Rotation Schedule

| Credential | Frequency | Trigger |
|------------|-----------|---------|
| Keepalived password | 90 days | Scheduled |
| Gateway stats credentials | 90 days | Scheduled |
| Qdrant API key | 180 days | Scheduled |
| SSH keys | 365 days | Scheduled |
| **All credentials** | Immediate | Leak/compromise |

### Rotation Process

**1. Generate New Credentials**:
```bash
# Regenerate .env (backs up existing to .env.backup)
./setup-env.sh

# Verify new values
diff .env.backup .env
```

**2. Update Terraform**:
```bash
# Export new variables
export $(grep -v '^#' .env | xargs)

# Regenerate configs
terraform apply -var="keepalived_auth_password=${KEEPALIVED_AUTH_PASSWORD}"
```

**3. Redeploy Affected Services**:

**Keepalived (Gateways)**:
```bash
# Copy new configs to gateways
scp generated/keepalived_gateway1.conf ubuntu@192.168.68.201:/etc/keepalived/keepalived.conf
scp generated/keepalived_gateway2.conf ubuntu@192.168.68.202:/etc/keepalived/keepalived.conf

# Restart keepalived
ssh ubuntu@192.168.68.201 'sudo systemctl restart keepalived'
ssh ubuntu@192.168.68.202 'sudo systemctl restart keepalived'

# Verify VIP failover works
ping 192.168.68.200
```

**Qdrant**:
```bash
# Update docker-compose-qdrant.yml with new QDRANT_API_KEY
# Restart container
docker-compose -f docker-compose-qdrant.yml down
docker-compose -f docker-compose-qdrant.yml up -d

# Test access
curl -H "api-key: ${QDRANT_API_KEY}" http://localhost:6335/collections
```

**4. Verify Access**:
```bash
# Test gateway stats (if enabled)
curl -u "${GATEWAY_STATS_CREDENTIALS}" http://192.168.68.200/stats

# Test Qdrant
curl -H "api-key: ${QDRANT_API_KEY}" http://localhost:6335/collections

# Test VIP failover
# Stop gateway1, ensure VIP moves to gateway2
```

**5. Update Dependent Systems**:
- MCP server configurations (`~/.claude.json`)
- CI/CD pipeline secrets
- Monitoring systems
- Documentation (if credentials referenced)

---

## Access Control

### SSH Key Management

**Generate SSH Key** (if not exists):
```bash
# Ed25519 (recommended)
ssh-keygen -t ed25519 -C "k8s-cluster-admin" -f ~/.ssh/id_ed25519_k8s

# Add to ssh-agent
ssh-add ~/.ssh/id_ed25519_k8s

# Copy public key to VMs (done by cloud-init)
cat ~/.ssh/id_ed25519_k8s.pub
```

**Key Rotation**:
```bash
# Generate new key
ssh-keygen -t ed25519 -C "k8s-cluster-admin-$(date +%Y%m)" -f ~/.ssh/id_ed25519_k8s_new

# Add to all VMs
for vm in 192.168.68.201 192.168.68.202 10.10.0.141 10.10.0.142 10.10.0.143 10.10.0.144 10.10.0.145; do
    ssh-copy-id -i ~/.ssh/id_ed25519_k8s_new.pub ubuntu@$vm
done

# Test new key
ssh -i ~/.ssh/id_ed25519_k8s_new ubuntu@192.168.68.201

# Remove old key from VMs
for vm in ...; do
    ssh ubuntu@$vm "sed -i '/old-key-fingerprint/d' ~/.ssh/authorized_keys"
done
```

### VM User Permissions

**Default Setup** (cloud-init):
```yaml
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL  # ⚠️ No password for sudo
    lock_passwd: false
    passwd: <hashed-password>
```

**Hardening for Production**:
```yaml
users:
  - name: ubuntu
    sudo: ALL=(ALL) ALL  # Require password for sudo
    lock_passwd: false
    passwd: <strong-hashed-password>

  - name: k8s-admin
    sudo: "ALL=(ALL) NOPASSWD:/usr/bin/kubectl,/usr/bin/kubeadm"  # Limited sudo
    groups: docker
    shell: /bin/bash
```

---

## Network Security

### Firewall Configuration

**Gateway Nodes** (external-facing):
```bash
# Allow only necessary ports
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp       # SSH
sudo ufw allow 6443/tcp     # K8s API (from LAN only)
sudo ufw allow 80/tcp       # HTTP
sudo ufw allow 443/tcp      # HTTPS
sudo ufw allow 9000/tcp     # HAProxy stats (restrict to admin IPs)
sudo ufw enable
```

**K8s Nodes** (internal):
```bash
# Internal network only (10.10.0.0/24)
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 10.10.0.0/24  # Allow all internal
sudo ufw allow 22/tcp              # SSH (from gateways only)
sudo ufw enable
```

### Network Segmentation

```
LAN (192.168.68.0/24)
  ↓
Gateways (dual-homed: LAN + Internal)
  ↓
Internal Network (10.10.0.0/24)
  ↓
K8s Cluster (control plane + workers)
```

**Security Benefits**:
- K8s nodes not directly accessible from LAN
- All external traffic filtered through gateways
- Gateway compromise doesn't expose internal network credentials
- VIP (192.168.68.200) provides single attack surface

---

## Incident Response

### Suspected Secret Leak

**1. Immediate Actions** (within 1 hour):
- [ ] Rotate all credentials immediately: `./setup-env.sh`
- [ ] Review recent git commits: `git log --all --full-history --source -- '*password*' '*secret*' '*key*'`
- [ ] Check GitHub/GitGuardian for alerts
- [ ] Disable compromised credentials in all systems
- [ ] Enable audit logging (if not already enabled)

**2. Investigation** (within 24 hours):
- [ ] Identify what was leaked (scope)
- [ ] Determine exposure window (when committed → when rotated)
- [ ] Review access logs for unauthorized access:
  - Gateway logs: `/var/log/nginx/access.log`
  - Qdrant logs: `docker logs qdrant-k8s`
  - K8s audit logs: `/var/log/kubernetes/audit.log`
- [ ] Check for lateral movement (compromised credentials used elsewhere)

**3. Remediation**:
- [ ] Clean git history (see [Cleaning Git History](#cleaning-git-history))
- [ ] Force collaborators to re-clone: `git clone <repo>`
- [ ] Update all dependent systems with new credentials
- [ ] Document incident (this file, runbook)

**4. Prevention**:
- [ ] Enable git-secrets pre-commit hooks
- [ ] Add CI/CD secret scanning (GitGuardian, TruffleHog)
- [ ] Require code review for all commits
- [ ] Regular secret rotation (automated if possible)

### Unauthorized Access Detected

**Signs**:
- Unexpected VIP failovers (check keepalived logs)
- Unknown pods/deployments in cluster
- Qdrant queries from unknown IPs
- Failed SSH authentication attempts (>/var/log/auth.log)

**Response**:
1. **Isolate**: Block source IPs via firewall
2. **Rotate**: All credentials immediately
3. **Audit**: Review all cluster resources, gateway configs, Qdrant data
4. **Restore**: From known-good snapshot if compromised
5. **Monitor**: Continuous monitoring for recurrence

---

## Compliance & Auditing

### Audit Log Locations

| Component | Log Path | Retention |
|-----------|----------|-----------|
| SSH access | `/var/log/auth.log` | 30 days |
| K8s API | `/var/log/kubernetes/audit.log` | 90 days |
| Nginx/HAProxy | `/var/log/nginx/access.log` | 7 days |
| Qdrant | Docker container logs | 7 days |
| Keepalived | `/var/log/syslog` | 30 days |

### Regular Security Audits

**Weekly**:
- [ ] Review failed SSH attempts: `sudo grep "Failed password" /var/log/auth.log`
- [ ] Check for unauthorized sudo usage: `sudo grep -i "sudo" /var/log/auth.log`
- [ ] Verify VIP status: `ip addr show | grep 192.168.68.200`

**Monthly**:
- [ ] Credential rotation review (are rotations on schedule?)
- [ ] Firewall rule review: `sudo ufw status numbered`
- [ ] K8s RBAC review: `kubectl get clusterrolebindings`
- [ ] Dependency updates: `terraform init -upgrade`

**Quarterly**:
- [ ] Penetration testing (simulated attacks)
- [ ] Secret scanning: `git secrets --scan --scan-history`
- [ ] Vulnerability scanning: `kubectl run trivy --image aquasec/trivy ...`
- [ ] Review this document for updates

---

## References

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [12-Factor App](https://12factor.net/config)
- [GitGuardian](https://www.gitguardian.com/)
- [git-secrets](https://github.com/awslabs/git-secrets)

---

## Change Log

### 2025-03-19 - Initial Security Documentation
- **Incident**: GitGuardian detected leaked `auth_password` in commits f584a5e, 43d9089
- **Resolution**:
  - Moved secret to environment variable (`KEEPALIVED_AUTH_PASSWORD`)
  - Updated `main.tf` to use `var.keepalived_auth_password`
  - Created `.env.example` template
  - Updated `.gitignore` to exclude `.env*` files
  - Created `setup-env.sh` for secure credential generation
  - Documented secret management practices
- **Lessons Learned**:
  - Never hardcode secrets in Terraform files
  - Use Terraform variables with `sensitive = true`
  - Implement git pre-commit hooks (git-secrets)
  - Regular secret scanning in CI/CD pipeline
