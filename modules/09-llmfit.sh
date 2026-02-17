#!/usr/bin/env bash
# =============================================================================
# 09-llmfit.sh — llmfit standalone binary (NO OpenClaw skill)
# =============================================================================
# Installs llmfit via the official curl installer. This is a standalone TUI
# tool that recommends right-sized LLM models for your hardware.
#
# The OpenClaw agent can access llmfit via `exec` in the main session
# (sandbox.mode is "non-main", so main session tools run on the host).
# NO skill file is installed in ~/.openclaw/skills/.
# =============================================================================

install_llmfit() {
    if run_as_user 'command -v llmfit &>/dev/null'; then
        log_info "llmfit already installed"
        return 0
    fi

    log_info "Installing llmfit via official installer..."
    run_as_user 'curl -fsSL https://llmfit.axjns.dev/install.sh | sh' || {
        log_warn "Curl installer failed — trying cargo if available..."
        if run_as_user 'command -v cargo &>/dev/null'; then
            run_as_user 'cargo install llmfit'
        else
            log_error "llmfit install failed (no cargo available). Install manually:"
            log_error "  curl -fsSL https://llmfit.axjns.dev/install.sh | sh"
            return 1
        fi
    }

    if run_as_user 'command -v llmfit &>/dev/null'; then
        log_success "llmfit installed"
    else
        log_warn "llmfit binary not found in PATH — may need shell restart"
    fi

    log_info "  Usage: llmfit (interactive TUI for model recommendations)"
    log_info "  Policy: NO OpenClaw skill installed — agent uses 'exec' in main session"
}
