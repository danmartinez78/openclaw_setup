#!/usr/bin/env bash
# =============================================================================
# 12-terminator.sh — Terminator terminal emulator
# =============================================================================

install_terminator() {
    if is_pkg_installed terminator; then
        log_info "Terminator already installed"
        return 0
    fi

    log_info "Installing Terminator..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq terminator

    log_success "Terminator installed"
}
