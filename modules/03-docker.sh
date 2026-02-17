#!/usr/bin/env bash
# =============================================================================
# 03-docker.sh — Docker Engine (official repo for Ubuntu 24.04 Noble)
# =============================================================================

install_docker() {
    if is_installed docker && docker info &>/dev/null; then
        log_info "Docker already installed: $(docker --version)"
        return 0
    fi

    log_info "Removing conflicting Docker packages..."
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        apt-get remove -y "$pkg" 2>/dev/null || true
    done

    log_info "Adding Docker GPG key..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    log_info "Adding Docker apt repository (Noble)..."
    cat > /etc/apt/sources.list.d/docker.sources << DOCKER_REPO
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
DOCKER_REPO

    log_info "Installing Docker Engine..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        docker-ce \
        docker-ce-cli \
        containerd.io \
        docker-buildx-plugin \
        docker-compose-plugin

    log_info "Adding ${REAL_USER} to docker group..."
    usermod -aG docker "$REAL_USER"

    log_info "Enabling and starting Docker service..."
    systemctl enable docker
    systemctl start docker

    # Verify
    if docker run --rm hello-world &>/dev/null; then
        log_success "Docker installed and verified: $(docker --version)"
    else
        log_warn "Docker installed but hello-world test failed (may need re-login for group)"
    fi
}
