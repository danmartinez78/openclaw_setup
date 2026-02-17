#!/usr/bin/env bash
# =============================================================================
# 16-python-uv.sh — Python uv package manager
# =============================================================================
# uv is a fast Python package manager recommended for vLLM development.
# Installed for the real user (not root).
# =============================================================================

install_python_uv() {
    if run_as_user 'command -v uv &>/dev/null'; then
        log_info "uv already installed: $(run_as_user 'uv --version')"
        return 0
    fi

    log_info "Installing uv for ${REAL_USER}..."
    run_as_user 'curl -LsSf https://astral.sh/uv/install.sh | sh'

    if run_as_user 'command -v uv &>/dev/null'; then
        log_success "uv installed: $(run_as_user 'uv --version')"
    else
        # uv installs to ~/.local/bin which may not be in PATH yet
        if [[ -f "${REAL_HOME}/.local/bin/uv" ]]; then
            log_success "uv installed at ~/.local/bin/uv (add to PATH or restart shell)"
        else
            log_warn "uv install may have failed — check: curl -LsSf https://astral.sh/uv/install.sh | sh"
        fi
    fi
}
