#!/usr/bin/env bash
# =============================================================================
# 15-gpu-monitoring.sh — GPU monitoring tools (nvtop + gpustat)
# =============================================================================
# nvtop: Interactive htop-like GPU monitor (excellent for multi-GPU)
# gpustat: Clean one-liner GPU status (great for scripting: gpustat -i 1)
# =============================================================================

install_gpu_monitoring() {
    # nvtop
    if is_pkg_installed nvtop; then
        log_info "nvtop already installed"
    else
        log_info "Installing nvtop..."
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nvtop
        log_success "nvtop installed — run: nvtop"
    fi

    # gpustat
    if is_installed gpustat; then
        log_info "gpustat already installed"
    else
        log_info "Installing gpustat..."
        pip3 install --break-system-packages gpustat
        log_success "gpustat installed — run: gpustat -i 1"
    fi

    log_info "GPU monitoring tools ready:"
    log_info "  nvtop     — interactive multi-GPU monitor (like htop for GPUs)"
    log_info "  gpustat   — quick GPU status: gpustat -i 1 (refresh every second)"
}
