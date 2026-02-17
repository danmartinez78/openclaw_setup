#!/usr/bin/env bash
# =============================================================================
# 05-ollama.sh — Ollama LLM server
# =============================================================================
# Installs Ollama via the official install script. Ollama auto-detects NVIDIA
# GPUs and runs as a systemd service.
# =============================================================================

install_ollama() {
    if is_installed ollama && is_service_active ollama; then
        log_info "Ollama already installed and running"
        return 0
    fi

    log_info "Installing Ollama..."
    curl -fsSL https://ollama.com/install.sh | sh

    # Verify service
    if is_service_active ollama; then
        log_success "Ollama installed and running"
        log_info "  Version: $(ollama --version 2>/dev/null | head -1)"
    else
        log_warn "Ollama installed but service not running — starting it"
        systemctl enable ollama
        systemctl start ollama
    fi

    # Check GPU detection
    if journalctl -u ollama --no-pager -n 50 2>/dev/null | grep -qi "nvidia\|cuda\|gpu"; then
        log_success "Ollama detected NVIDIA GPU(s)"
    else
        log_warn "Could not confirm GPU detection — check: journalctl -u ollama"
    fi

    log_info "Pull a model to get started: ollama pull llama3.2:3b"
}
