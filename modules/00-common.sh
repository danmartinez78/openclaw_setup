#!/usr/bin/env bash
# =============================================================================
# 00-common.sh — Shared utility functions for all modules
# =============================================================================
# Sourced by setup.sh before any module runs. Provides:
#   - Colored logging (log_info, log_warn, log_error, log_success)
#   - Idempotency helpers (is_installed, is_service_active)
#   - Checkpoint system (mark_complete, is_complete, require_reboot)
#   - User detection (REAL_USER, REAL_HOME)
# =============================================================================

set -euo pipefail

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKPOINT_FILE="${SCRIPT_DIR}/.checkpoint"
LOG_FILE="${SCRIPT_DIR}/setup.log"

# --- Detect the real (non-root) user ---
if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_USER="$SUDO_USER"
else
    REAL_USER="$(whoami)"
fi
REAL_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

# =============================================================================
# Logging
# =============================================================================

_log() {
    local level="$1" color="$2"
    shift 2
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo -e "${color}[${level}]${NC} ${timestamp} $*"
    echo "[${level}] ${timestamp} $*" >> "$LOG_FILE"
}

log_info()    { _log "INFO"    "$BLUE"   "$@"; }
log_warn()    { _log "WARN"    "$YELLOW" "$@"; }
log_error()   { _log "ERROR"   "$RED"    "$@"; }
log_success() { _log "OK"      "$GREEN"  "$@"; }

log_header() {
    local msg="$1"
    echo ""
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  ${msg}${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "[HEADER] $(date '+%Y-%m-%d %H:%M:%S') ${msg}" >> "$LOG_FILE"
}

# =============================================================================
# Idempotency Helpers
# =============================================================================

is_installed() {
    command -v "$1" &>/dev/null
}

is_pkg_installed() {
    dpkg -l "$1" 2>/dev/null | grep -q "^ii"
}

is_service_active() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

is_service_enabled() {
    systemctl is-enabled --quiet "$1" 2>/dev/null
}

# =============================================================================
# Checkpoint System
# =============================================================================
# Tracks completed modules in .checkpoint file so the script can resume after
# a reboot (required after NVIDIA driver install).

mark_complete() {
    local module="$1"
    touch "$CHECKPOINT_FILE"
    if ! grep -qxF "$module" "$CHECKPOINT_FILE" 2>/dev/null; then
        echo "$module" >> "$CHECKPOINT_FILE"
    fi
    log_success "Module ${module} completed"
}

is_complete() {
    local module="$1"
    [[ -f "$CHECKPOINT_FILE" ]] && grep -qxF "$module" "$CHECKPOINT_FILE" 2>/dev/null
}

require_reboot() {
    local reason="$1"
    echo ""
    echo -e "${BOLD}${YELLOW}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${YELLOW}║                    REBOOT REQUIRED                           ║${NC}"
    echo -e "${BOLD}${YELLOW}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}${YELLOW}║  ${reason}${NC}"
    echo -e "${BOLD}${YELLOW}║                                                              ║${NC}"
    echo -e "${BOLD}${YELLOW}║  After reboot, re-run:  sudo ./setup.sh                      ║${NC}"
    echo -e "${BOLD}${YELLOW}║  The script will resume from where it left off.               ║${NC}"
    echo -e "${BOLD}${YELLOW}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    log_warn "Reboot required: ${reason}"
    read -rp "Reboot now? [Y/n] " answer
    if [[ "${answer,,}" != "n" ]]; then
        log_info "Rebooting..."
        reboot
    else
        log_warn "Please reboot manually, then re-run: sudo ./setup.sh"
        exit 0
    fi
}

# =============================================================================
# Run-as-user helper
# =============================================================================
# Runs a command as the real (non-root) user, preserving their environment.

run_as_user() {
    sudo -H -u "$REAL_USER" bash -c "$*"
}

# =============================================================================
# Safe download helper
# =============================================================================

safe_download() {
    local url="$1" dest="$2"
    if [[ -f "$dest" ]]; then
        log_info "Already downloaded: ${dest}"
        return 0
    fi
    log_info "Downloading: ${url}"
    curl -fsSL -o "$dest" "$url"
}
