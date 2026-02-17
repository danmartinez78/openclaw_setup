#!/usr/bin/env bash
# =============================================================================
# 14-portainer.sh — Portainer CE (Docker web UI)
# =============================================================================
# Runs Portainer as a Docker container bound to 127.0.0.1 only.
# Access remotely via Tailscale or SSH tunnel.
# =============================================================================

install_portainer() {
    if ! is_installed docker; then
        log_error "Docker required. Run module 03-docker first."
        return 1
    fi

    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -qx portainer; then
        if docker ps --format '{{.Names}}' | grep -qx portainer; then
            log_info "Portainer already running"
            return 0
        fi
        log_info "Portainer container exists but stopped — starting..."
        docker start portainer
        log_success "Portainer started"
        return 0
    fi

    log_info "Creating Portainer data volume..."
    docker volume create portainer_data

    log_info "Starting Portainer CE (bound to 127.0.0.1:${PORTAINER_PORT})..."
    docker run -d \
        -p "127.0.0.1:${PORTAINER_PORT}:9443" \
        --name portainer \
        --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest

    if docker ps --format '{{.Names}}' | grep -qx portainer; then
        log_success "Portainer running at https://127.0.0.1:${PORTAINER_PORT}"
        log_info "  First visit: create an admin account"
        log_info "  Remote access: use Tailscale or SSH tunnel"
    else
        log_error "Portainer failed to start — check: docker logs portainer"
    fi
}
