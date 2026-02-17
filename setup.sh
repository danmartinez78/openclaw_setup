#!/usr/bin/env bash
# =============================================================================
# setup.sh — Ubuntu 24.04 Bulletproof Setup Script
# =============================================================================
# Installs and configures: NVIDIA drivers + CUDA, Docker, NVIDIA Container
# Toolkit, Ollama, vLLM, OpenClaw (security-hardened), Tailscale, llmfit,
# VS Code, Terminator, NoMachine, Portainer, GPU monitoring, and more.
#
# Usage:
#   sudo ./setup.sh            # First run (installs everything)
#   sudo ./setup.sh            # After reboot (resumes from checkpoint)
#   sudo ./setup.sh --reset    # Clear checkpoints and start fresh
#   sudo ./setup.sh --status   # Show what's installed
#
# The script is idempotent — safe to re-run at any time.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Fix Windows line endings (CRLF → LF) if needed ---
if grep -qP '\r$' "${BASH_SOURCE[0]}" 2>/dev/null; then
    echo "Fixing Windows line endings..."
    if command -v dos2unix &>/dev/null; then
        dos2unix "${SCRIPT_DIR}/config.env" "${SCRIPT_DIR}/setup.sh" "${SCRIPT_DIR}"/modules/*.sh 2>/dev/null
    else
        sed -i 's/\r$//' "${SCRIPT_DIR}/config.env" "${SCRIPT_DIR}/setup.sh" "${SCRIPT_DIR}"/modules/*.sh
    fi
    echo "Fixed. Re-running..."
    exec bash "${BASH_SOURCE[0]}" "$@"
fi

# --- Root check ---
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root (use sudo)."
    echo "  Usage: sudo ./setup.sh"
    exit 1
fi

# --- Source config ---
if [[ ! -f "${SCRIPT_DIR}/config.env" ]]; then
    if [[ -f "${SCRIPT_DIR}/config.env.example" ]]; then
        cp "${SCRIPT_DIR}/config.env.example" "${SCRIPT_DIR}/config.env"
        echo "Created config.env from template. Edit it to set API keys, then re-run."
        exit 0
    else
        echo "ERROR: config.env not found. Copy config.env.example to config.env and edit it."
        exit 1
    fi
fi
# shellcheck source=config.env
source "${SCRIPT_DIR}/config.env"

# --- Source common utilities ---
# shellcheck source=modules/00-common.sh
source "${SCRIPT_DIR}/modules/00-common.sh"

# --- Handle args ---
case "${1:-}" in
    --reset)
        log_warn "Clearing all checkpoints..."
        rm -f "$CHECKPOINT_FILE"
        log_success "Checkpoints cleared. Re-run to start fresh."
        exit 0
        ;;
    --status)
        log_header "Installation Status"
        if [[ -f "$CHECKPOINT_FILE" ]]; then
            while IFS= read -r module; do
                echo -e "  ${GREEN}✓${NC} ${module}"
            done < "$CHECKPOINT_FILE"
        else
            echo "  No modules completed yet."
        fi
        echo ""
        exit 0
        ;;
    --test-tailscale)
        log_header "Tailscale Connectivity Test"
        source "${SCRIPT_DIR}/modules/08-tailscale.sh"
        _tailscale_verify
        exit 0
        ;;
    "")
        ;; # Normal run
    *)
        echo "Usage: sudo ./setup.sh [--reset|--status|--test-tailscale]"
        exit 1
        ;;
esac

# --- Start ---
log_header "Ubuntu 24.04 Setup — Starting"
log_info "User: ${REAL_USER} | Home: ${REAL_HOME}"
log_info "Log file: ${LOG_FILE}"

if [[ -f "$CHECKPOINT_FILE" ]]; then
    completed=$(wc -l < "$CHECKPOINT_FILE")
    log_info "Resuming — ${completed} module(s) already completed"
fi

# =============================================================================
# Module execution
# =============================================================================
# Each module is sourced and its install function called. The module name
# matches the checkpoint key. If already complete, it's skipped.

run_module() {
    local module_file="$1"
    local module_name
    module_name="$(basename "$module_file" .sh)"

    # Skip the common module
    [[ "$module_name" == "00-common" ]] && return 0

    # Check feature flag — extract the component name from module filename
    local component
    component="$(echo "$module_name" | sed 's/^[0-9]*-//')"
    local flag_name="INSTALL_$(echo "$component" | tr '[:lower:]-' '[:upper:]_')"

    # Check if the feature flag exists and is "false"
    if [[ -v "$flag_name" ]] && [[ "${!flag_name}" == "false" ]]; then
        log_info "Skipping ${module_name} (${flag_name}=false)"
        return 0
    fi

    # Check checkpoint
    if is_complete "$module_name"; then
        log_info "Skipping ${module_name} (already complete)"
        return 0
    fi

    log_header "Installing: ${module_name}"

    # Source and run
    # shellcheck source=/dev/null
    source "${module_file}"

    local func_name="install_${component//-/_}"
    if declare -f "$func_name" &>/dev/null; then
        "$func_name"
        mark_complete "$module_name"
    else
        log_error "No function '${func_name}' found in ${module_file}"
        return 1
    fi
}

# Run all modules in order
for module in "${SCRIPT_DIR}"/modules/[0-9]*.sh; do
    [[ -f "$module" ]] || continue
    run_module "$module"
done

# =============================================================================
# Final Summary
# =============================================================================

log_header "Setup Complete!"

echo -e "${BOLD}Installed components:${NC}"
echo ""

# Collect version info
declare -A VERSIONS=(
    ["NVIDIA Driver"]="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || echo 'not installed')"
    ["CUDA"]="$(nvcc --version 2>/dev/null | grep 'release' | sed 's/.*release //' | sed 's/,.*//' || echo 'not installed')"
    ["Docker"]="$(docker --version 2>/dev/null | sed 's/Docker version //' | sed 's/,.*//' || echo 'not installed')"
    ["Ollama"]="$(ollama --version 2>/dev/null | head -1 || echo 'not installed')"
    ["Node.js"]="$(node --version 2>/dev/null || echo 'not installed')"
    ["Tailscale"]="$(tailscale version 2>/dev/null | head -1 || echo 'not installed')"
    ["llmfit"]="$(run_as_user 'llmfit --version 2>/dev/null || echo not\ installed')"
    ["VS Code"]="$(code --version 2>/dev/null | head -1 || echo 'not installed')"
    ["nvtop"]="$(nvtop --version 2>/dev/null | head -1 || echo 'not installed')"
    ["uv"]="$(run_as_user 'uv --version 2>/dev/null || echo not\ installed')"
)

for component in "${!VERSIONS[@]}"; do
    version="${VERSIONS[$component]}"
    if [[ "$version" == "not installed" ]]; then
        echo -e "  ${YELLOW}○${NC} ${component}: ${YELLOW}${version}${NC}"
    else
        echo -e "  ${GREEN}●${NC} ${component}: ${GREEN}${version}${NC}"
    fi
done

echo ""
echo -e "${BOLD}Services:${NC}"
for svc in docker ollama nxserver tailscaled; do
    if is_service_active "$svc"; then
        echo -e "  ${GREEN}●${NC} ${svc}: ${GREEN}running${NC}"
    else
        echo -e "  ${YELLOW}○${NC} ${svc}: ${YELLOW}not running${NC}"
    fi
done

echo ""
echo -e "${BOLD}Docker containers:${NC}"
docker ps --format "  {{.Names}}: {{.Status}}" 2>/dev/null || echo "  (docker not available)"

echo ""
echo -e "${BOLD}Security:${NC}"
if [[ -d "${REAL_HOME}/.openclaw" ]]; then
    local_perms="$(stat -c '%a' "${REAL_HOME}/.openclaw" 2>/dev/null || echo '???')"
    echo -e "  ~/.openclaw/ permissions: ${local_perms}"
    if [[ -f "${REAL_HOME}/.openclaw/openclaw.json" ]]; then
        config_perms="$(stat -c '%a' "${REAL_HOME}/.openclaw/openclaw.json" 2>/dev/null || echo '???')"
        echo -e "  openclaw.json permissions: ${config_perms}"
    fi
    skill_count="$(find "${REAL_HOME}/.openclaw/skills/" -name "SKILL.md" 2>/dev/null | wc -l)"
    echo -e "  Third-party skills installed: ${skill_count}"
fi

echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Run 'tailscale up' if not yet authenticated"
echo "  2. Configure OpenClaw API keys in ~/.openclaw/openclaw.json"
echo "  3. Pull an Ollama model: ollama pull llama3.2:3b"
echo "  4. Access Portainer: https://127.0.0.1:${PORTAINER_PORT}"
echo "  5. GPU monitor: nvtop"
echo ""
log_info "Full log: ${LOG_FILE}"
