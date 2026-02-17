#!/usr/bin/env bash
# =============================================================================
# 02-nvidia-driver.sh — NVIDIA GPU driver + CUDA toolkit
# =============================================================================
# Installs the 'cuda' metapackage which includes both the driver and CUDA
# toolkit. A reboot is required after this step for kernel modules to load.
# =============================================================================

install_nvidia_driver() {
    # Check if driver is already working
    if is_installed nvidia-smi && nvidia-smi &>/dev/null; then
        log_info "NVIDIA driver already installed and working"
        nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | while read -r line; do
            log_info "  GPU: ${line}"
        done
        return 0
    fi

    # Check if cuda-keyring is already installed
    if ! is_pkg_installed cuda-keyring; then
        log_info "Installing CUDA keyring for Ubuntu 24.04..."
        local keyring_deb="/tmp/cuda-keyring.deb"
        safe_download \
            "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb" \
            "$keyring_deb"
        dpkg -i "$keyring_deb"
        rm -f "$keyring_deb"
    fi

    log_info "Updating package lists with CUDA repo..."
    apt-get update -qq

    log_info "Installing CUDA (driver + toolkit)... This may take a while."
    DEBIAN_FRONTEND=noninteractive apt-get install -y cuda

    # Set up CUDA environment for all users
    log_info "Configuring CUDA environment..."
    cat > /etc/profile.d/cuda.sh << 'CUDA_ENV'
# CUDA environment — added by openclaw_setup
if [ -d /usr/local/cuda/bin ]; then
    export PATH="/usr/local/cuda/bin:$PATH"
fi
if [ -d /usr/local/cuda/lib64 ]; then
    export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"
fi
CUDA_ENV
    chmod 644 /etc/profile.d/cuda.sh

    log_success "NVIDIA driver + CUDA installed"
    log_warn "A reboot is required for the GPU kernel modules to load."

    # Mark complete before reboot so we don't re-run this module
    mark_complete "02-nvidia-driver"

    require_reboot "NVIDIA kernel modules need loading."
}
