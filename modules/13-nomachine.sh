#!/usr/bin/env bash
# =============================================================================
# 13-nomachine.sh — NoMachine remote desktop
# =============================================================================
# NoMachine is not in Ubuntu repos — downloads a pinned .deb from the vendor.
# Version is configurable in config.env (NOMACHINE_VERSION / NOMACHINE_BUILD).
# =============================================================================

install_nomachine() {
    if is_pkg_installed nomachine; then
        log_info "NoMachine already installed"
        return 0
    fi

    local version="${NOMACHINE_VERSION}"
    local major_minor
    major_minor="$(echo "$version" | cut -d. -f1-2)"
    local deb_file="/tmp/nomachine_${version}_amd64.deb"
    local download_url="https://download.nomachine.com/download/${major_minor}/Linux/nomachine_${version}_amd64.deb"

    log_info "Downloading NoMachine ${version}..."
    safe_download "$download_url" "$deb_file"

    log_info "Installing NoMachine..."
    dpkg -i "$deb_file" || {
        log_info "Resolving dependencies..."
        apt-get install -f -y -qq
    }
    rm -f "$deb_file"

    if is_service_active nxserver; then
        log_success "NoMachine installed and running"
    else
        log_success "NoMachine installed (service will start on next login)"
    fi
}
