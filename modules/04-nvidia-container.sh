#!/usr/bin/env bash
# =============================================================================
# 04-nvidia-container.sh — NVIDIA Container Toolkit
# =============================================================================
# Bridges Docker and NVIDIA GPUs so containers can access GPU hardware.
# Requires: NVIDIA driver (02) + Docker (03) already installed.
# =============================================================================

install_nvidia_container() {
    # Verify prerequisites
    if ! is_installed nvidia-smi; then
        log_error "NVIDIA driver not found. Run module 02-nvidia-driver first."
        return 1
    fi
    if ! is_installed docker; then
        log_error "Docker not found. Run module 03-docker first."
        return 1
    fi

    if is_pkg_installed nvidia-container-toolkit; then
        log_info "NVIDIA Container Toolkit already installed"
    else
        log_info "Adding NVIDIA Container Toolkit GPG key..."
        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
            | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

        log_info "Adding NVIDIA Container Toolkit apt repository..."
        curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
            | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
            > /etc/apt/sources.list.d/nvidia-container-toolkit.list

        log_info "Installing NVIDIA Container Toolkit..."
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nvidia-container-toolkit
    fi

    log_info "Configuring Docker runtime for NVIDIA..."
    nvidia-ctk runtime configure --runtime=docker

    log_info "Restarting Docker to apply NVIDIA runtime..."
    systemctl restart docker

    # Verify GPU access from Docker
    log_info "Verifying GPU access from Docker containers..."
    if docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu24.04 nvidia-smi &>/dev/null; then
        log_success "NVIDIA Container Toolkit working — GPUs accessible from Docker"
        docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu24.04 \
            nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | while read -r gpu; do
            log_info "  Container GPU: ${gpu}"
        done
    else
        log_warn "GPU test container failed — may need to pull the image first or check driver"
    fi
}
