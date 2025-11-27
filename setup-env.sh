#!/bin/bash
# ==============================================================================
# Environment Setup Script for K8s Cluster
# ==============================================================================
# Purpose: Initialize .env file with secure random passwords
# Usage:   ./setup-env.sh
# ==============================================================================

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${PROJECT_DIR}/.env"
ENV_EXAMPLE="${PROJECT_DIR}/.env.example"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log() {
    echo -e "${CYAN}[setup-env]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if .env already exists
if [[ -f "$ENV_FILE" ]]; then
    warn ".env file already exists at: $ENV_FILE"
    read -p "Overwrite existing .env? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Keeping existing .env file"
        exit 0
    fi
    log "Backing up existing .env to .env.backup"
    cp "$ENV_FILE" "${ENV_FILE}.backup"
fi

# Check if .env.example exists
if [[ ! -f "$ENV_EXAMPLE" ]]; then
    error ".env.example not found. Cannot proceed."
fi

# Generate secure random passwords
log "Generating secure random passwords..."

# Keepalived auth password (max 8 chars for VRRP spec)
KEEPALIVED_PASS=$(openssl rand -base64 8 | tr -d '/+=' | head -c 8)

# Gateway stats credentials
STATS_USER="admin"
STATS_PASS=$(openssl rand -base64 12 | tr -d '/+=')

# Qdrant API key (32 chars hex)
QDRANT_KEY=$(openssl rand -hex 16)

# Create .env file
log "Creating .env file..."
cat > "$ENV_FILE" << EOF
# ==============================================================================
# K8s Cluster Environment Variables
# ==============================================================================
# SECURITY: This file contains secrets - NEVER commit to git
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# ==============================================================================

# Keepalived VRRP Authentication (max 8 chars)
KEEPALIVED_AUTH_PASSWORD="${KEEPALIVED_PASS}"

# Gateway Stats Credentials (HAProxy/Nginx monitoring)
GATEWAY_STATS_CREDENTIALS="${STATS_USER}:${STATS_PASS}"

# Qdrant Vector Database API Key
QDRANT_API_KEY="${QDRANT_KEY}"

# Optional: APT cache server password (if using authenticated apt-cacher-ng)
# APT_CACHE_PASSWORD=""
EOF

# Set restrictive permissions
chmod 600 "$ENV_FILE"

success ".env file created at: $ENV_FILE"
log ""
log "Generated credentials:"
log "  • Keepalived auth: ${KEEPALIVED_PASS}"
log "  • Gateway stats:   ${STATS_USER}:${STATS_PASS}"
log "  • Qdrant API key:  ${QDRANT_KEY}"
log ""
warn "IMPORTANT: Store these credentials securely (password manager)"
log ""
log "Next steps:"
log "  1. Review .env file and adjust if needed"
log "  2. Export variables before running Terraform:"
log "     export \$(grep -v '^#' .env | xargs)"
log "  3. Or use with Terraform:"
log "     terraform apply -var=\"keepalived_auth_password=\${KEEPALIVED_AUTH_PASSWORD}\""
log ""
