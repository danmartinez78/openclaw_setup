#!/usr/bin/env bash
# =============================================================================
# 11-vscode.sh — Visual Studio Code
# =============================================================================

install_vscode() {
    if is_installed code; then
        log_info "VS Code already installed: $(code --version 2>/dev/null | head -1)"
        return 0
    fi

    log_info "Adding Microsoft GPG key and repository..."
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | gpg --dearmor -o /usr/share/keyrings/microsoft-archive-keyring.gpg

    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft-archive-keyring.gpg] https://packages.microsoft.com/repos/code stable main" \
        > /etc/apt/sources.list.d/vscode.list

    log_info "Installing VS Code..."
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq code

    log_success "VS Code installed: $(code --version 2>/dev/null | head -1)"
}
