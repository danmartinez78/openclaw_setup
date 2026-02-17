#!/usr/bin/env bash
# =============================================================================
# 06-node.sh — Node.js 22 LTS via NodeSource
# =============================================================================
# Required by OpenClaw (Node >= 22). Also enables corepack for pnpm support.
# =============================================================================

install_node() {
    if is_installed node; then
        local current_major
        current_major="$(node --version 2>/dev/null | sed 's/v//' | cut -d. -f1)"
        if [[ "$current_major" -ge "${NODE_VERSION}" ]]; then
            log_info "Node.js already installed: $(node --version)"
            return 0
        fi
        log_warn "Node.js ${current_major} found but need >= ${NODE_VERSION}, upgrading..."
    fi

    log_info "Adding NodeSource repository for Node.js ${NODE_VERSION}..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -

    log_info "Installing Node.js ${NODE_VERSION}..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs

    log_info "Enabling corepack (for pnpm)..."
    corepack enable || log_warn "corepack enable failed — pnpm can be installed manually"

    log_success "Node.js installed: $(node --version)"
    log_info "  npm: $(npm --version)"
}
