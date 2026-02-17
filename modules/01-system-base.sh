#!/usr/bin/env bash
# =============================================================================
# 01-system-base.sh — Base system packages and updates
# =============================================================================

install_system_base() {
    log_info "Updating package lists..."
    apt-get update -qq

    log_info "Upgrading installed packages..."
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

    log_info "Installing base development tools..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        build-essential \
        git \
        curl \
        wget \
        htop \
        tmux \
        vim \
        nano \
        jq \
        unzip \
        zip \
        tree \
        net-tools \
        iproute2 \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        python3 \
        python3-pip \
        python3-venv \
        pkg-config \
        dirmngr \
        gpg-agent

    log_success "Base system packages installed"
}
