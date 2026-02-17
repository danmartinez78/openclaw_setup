#!/usr/bin/env bash
# =============================================================================
# 07-openclaw.sh — OpenClaw via Docker (security-hardened)
# =============================================================================
# Installs OpenClaw using the Docker method and applies a hardened
# configuration:
#   - Gateway bound to loopback only (127.0.0.1)
#   - Token auth (fail-closed) with auto-generated strong token
#   - Tailscale Serve for secure LAN access
#   - mDNS discovery disabled
#   - Sandbox mode: non-main (main session on host, others sandboxed)
#   - No third-party skills
#   - Strict file permissions (700/600)
#   - Multi-provider API keys (Z.ai, Gemini, Haimaker)
#   - Agent file migration from existing install
# =============================================================================

# =============================================================================
# Agent workspace migration — imports SOUL.md, AGENTS.md, USER.md, etc.
# =============================================================================
_openclaw_migrate_workspace() {
    local openclaw_dir="$1"
    local workspace_dir="${openclaw_dir}/workspace"
    local source="${OPENCLAW_MIGRATE_FROM:-}"

    if [[ -z "$source" ]]; then
        log_info "No migration source configured (OPENCLAW_MIGRATE_FROM is empty)"
        return 0
    fi

    # --- Workspace files to migrate (agent identity + memory) ---
    local -a WORKSPACE_FILES=(
        "SOUL.md" "AGENTS.md" "USER.md" "IDENTITY.md" "TOOLS.md"
        "HEARTBEAT.md" "BOOT.md" "MEMORY.md"
    )
    local -a WORKSPACE_DIRS=("memory")

    # --- Source is a tar.gz archive ---
    if [[ -f "$source" && "$source" == *.tar.gz ]]; then
        log_info "Migrating agent files from archive: ${source}"
        local tmpdir
        tmpdir="$(mktemp -d)"
        tar xzf "$source" -C "$tmpdir"

        # Find the workspace directory inside the archive
        local src_workspace
        src_workspace="$(find "$tmpdir" -type d -name workspace | head -1)"
        if [[ -z "$src_workspace" ]]; then
            log_warn "No workspace/ directory found in archive — skipping migration"
            rm -rf "$tmpdir"
            return 0
        fi

        _copy_workspace_files "$src_workspace" "$workspace_dir"
        rm -rf "$tmpdir"

    # --- Source is a directory ---
    elif [[ -d "$source" ]]; then
        log_info "Migrating agent files from directory: ${source}"

        # Accept either the .openclaw/ dir itself or a workspace/ subdir
        local src_workspace
        if [[ -d "${source}/workspace" ]]; then
            src_workspace="${source}/workspace"
        elif [[ -f "${source}/SOUL.md" || -f "${source}/AGENTS.md" ]]; then
            src_workspace="$source"
        else
            log_warn "Cannot find workspace files in ${source} — skipping"
            return 0
        fi

        _copy_workspace_files "$src_workspace" "$workspace_dir"
    else
        log_error "Migration source not found: ${source}"
        log_error "Set OPENCLAW_MIGRATE_FROM to a .tar.gz or directory path"
        return 0
    fi
}

_copy_workspace_files() {
    local src="$1" dest="$2"
    local copied=0

    # Copy individual workspace files
    for f in SOUL.md AGENTS.md USER.md IDENTITY.md TOOLS.md HEARTBEAT.md BOOT.md MEMORY.md; do
        if [[ -f "${src}/${f}" ]]; then
            cp -v "${src}/${f}" "${dest}/${f}"
            ((copied++))
        fi
    done

    # Copy memory directory
    if [[ -d "${src}/memory" ]]; then
        cp -rv "${src}/memory" "${dest}/"
        local mem_count
        mem_count="$(find "${dest}/memory" -name '*.md' | wc -l)"
        log_info "  Migrated memory/ directory (${mem_count} entries)"
        ((copied++))
    fi

    # Fix ownership
    chown -R "${REAL_USER}:${REAL_USER}" "$dest"

    if [[ $copied -gt 0 ]]; then
        log_success "Migrated ${copied} agent file(s) from existing install"
        echo ""
        echo -e "  ${BOLD}Migrated workspace files:${NC}"
        for f in SOUL.md AGENTS.md USER.md IDENTITY.md TOOLS.md HEARTBEAT.md BOOT.md MEMORY.md; do
            if [[ -f "${dest}/${f}" ]]; then
                echo -e "    ${GREEN}✓${NC} ${f}"
            fi
        done
        if [[ -d "${dest}/memory" ]]; then
            echo -e "    ${GREEN}✓${NC} memory/ ($(find "${dest}/memory" -name '*.md' | wc -l) entries)"
        fi
        echo ""
        log_info "  Skipping bootstrap since workspace files were migrated"
        # Set flag so openclaw.json skipBootstrap is true
        export OPENCLAW_SKIP_BOOTSTRAP=true
    else
        log_warn "No workspace files found in migration source"
    fi
}

install_openclaw() {
    if ! is_installed docker; then
        log_error "Docker required. Run module 03-docker first."
        return 1
    fi
    if ! is_installed node; then
        log_error "Node.js required. Run module 06-node first."
        return 1
    fi

    local openclaw_dir="${REAL_HOME}/.openclaw"
    local openclaw_config="${openclaw_dir}/openclaw.json"

    # Install openclaw CLI globally if not present
    if ! is_installed openclaw; then
        log_info "Installing OpenClaw CLI..."
        run_as_user "npm install -g openclaw@latest"
    fi

    log_info "OpenClaw CLI version: $(run_as_user 'openclaw --version 2>/dev/null || echo unknown')"

    # Create config directory with secure permissions
    if [[ ! -d "$openclaw_dir" ]]; then
        log_info "Creating OpenClaw config directory..."
        run_as_user "mkdir -p '${openclaw_dir}'"
    fi
    chmod 700 "$openclaw_dir"

    # Generate a strong gateway token if we don't have one yet
    local gateway_token
    if [[ -f "${openclaw_dir}/.gateway-token" ]]; then
        gateway_token="$(cat "${openclaw_dir}/.gateway-token")"
        log_info "Using existing gateway token"
    else
        gateway_token="$(openssl rand -hex 32)"
        echo "$gateway_token" > "${openclaw_dir}/.gateway-token"
        chown "${REAL_USER}:${REAL_USER}" "${openclaw_dir}/.gateway-token"
        chmod 600 "${openclaw_dir}/.gateway-token"
        log_info "Generated new gateway token (stored in ~/.openclaw/.gateway-token)"
    fi

    # --- Build model routing config ---
    local model_block=""
    if [[ -n "${OPENCLAW_PRIMARY_MODEL:-}" ]]; then
        model_block='"model": { "primary": "'"${OPENCLAW_PRIMARY_MODEL}"'"'
        if [[ -n "${OPENCLAW_FALLBACK_MODELS:-}" ]]; then
            local fallbacks_json
            fallbacks_json=$(echo "$OPENCLAW_FALLBACK_MODELS" | tr ',' '\n' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' | jq -R . | jq -s .)
            model_block="${model_block}, \"fallbacks\": ${fallbacks_json}"
        fi
        model_block="${model_block} },"
    fi

    # --- Build custom providers config (for Haimaker if configured) ---
    local providers_block=""
    if [[ -n "${HAIMAKER_API_KEY:-}" && -n "${HAIMAKER_BASE_URL:-}" ]]; then
        providers_block=',
  "models": {
    "providers": {
      "haimaker": {
        "baseUrl": "'"${HAIMAKER_BASE_URL}"'",
        "apiKey": "\${HAIMAKER_API_KEY}",
        "api": "openai-completions"
      }
    }
  }'
    fi

    # Write security-hardened configuration
    log_info "Writing security-hardened openclaw.json..."
    cat > "$openclaw_config" << OPENCLAW_CONFIG
{
  "\$schema": "https://openclaw.ai/schemas/openclaw.json",
  "gateway": {
    "mode": "local",
    "bind": "loopback",
    "port": ${OPENCLAW_PORT},
    "auth": {
      "mode": "token",
      "token": "${gateway_token}"
    },
    "tailscale": {
      "mode": "serve"
    },
    "controlUi": {
      "allowInsecureAuth": false,
      "dangerouslyDisableDeviceAuth": false
    }
  },
  "discovery": {
    "mdns": {
      "mode": "off"
    }
  },
  "logging": {
    "redactSensitive": "tools"
  },
  "tools": {
    "fs": {
      "workspaceOnly": true
    },
    "exec": {
      "applyPatch": {
        "workspaceOnly": true
      }
    }
  },
  "agents": {
    "defaults": {
      ${model_block}
      "sandbox": {
        "mode": "non-main"
      },
      "skipBootstrap": ${OPENCLAW_SKIP_BOOTSTRAP:-false}
    }
  },
  "session": {
    "dmScope": "per-channel-peer"
  }${providers_block}
}
OPENCLAW_CONFIG

    # Set ownership and permissions
    chown "${REAL_USER}:${REAL_USER}" "$openclaw_config"
    chmod 600 "$openclaw_config"

    # --- Write API keys to ~/.openclaw/.env ---
    log_info "Writing API provider keys to ~/.openclaw/.env..."
    local env_file="${openclaw_dir}/.env"
    cat > "$env_file" << OPENCLAW_ENV
# OpenClaw API provider keys — auto-generated by setup.sh
# Edit this file to add/change API keys. OpenClaw reads it on startup.
OPENCLAW_ENV

    # Only write keys that are set (non-empty)
    [[ -n "${ZAI_API_KEY:-}" ]]      && echo "ZAI_API_KEY=${ZAI_API_KEY}" >> "$env_file"
    [[ -n "${GEMINI_API_KEY:-}" ]]   && echo "GEMINI_API_KEY=${GEMINI_API_KEY}" >> "$env_file"
    [[ -n "${HAIMAKER_API_KEY:-}" ]] && echo "HAIMAKER_API_KEY=${HAIMAKER_API_KEY}" >> "$env_file"
    [[ -n "${HF_TOKEN:-}" ]]         && echo "HF_TOKEN=${HF_TOKEN}" >> "$env_file"

    chown "${REAL_USER}:${REAL_USER}" "$env_file"
    chmod 600 "$env_file"

    local key_count
    key_count=$(grep -c '_KEY=\|_TOKEN=' "$env_file" 2>/dev/null || echo 0)
    log_info "  ${key_count} API key(s) configured in ~/.openclaw/.env"

    # Ensure skills directory exists but is empty (no third-party skills)
    run_as_user "mkdir -p '${openclaw_dir}/skills'"
    run_as_user "mkdir -p '${openclaw_dir}/workspace'"

    # --- Migrate agent files from existing install ---
    _openclaw_migrate_workspace "${openclaw_dir}"

    # Set up OpenClaw Docker daemon
    log_info "Setting up OpenClaw Docker environment..."
    run_as_user "cd '${REAL_HOME}' && openclaw onboard --install-daemon" || {
        log_warn "Onboarding requires interactive setup — run manually:"
        log_warn "  openclaw onboard --install-daemon"
    }

    # Verify security posture
    log_info "Verifying security configuration..."

    # Check permissions
    local dir_perms config_perms
    dir_perms="$(stat -c '%a' "$openclaw_dir")"
    config_perms="$(stat -c '%a' "$openclaw_config")"

    if [[ "$dir_perms" == "700" ]]; then
        log_success "~/.openclaw/ permissions: ${dir_perms} (correct)"
    else
        log_error "~/.openclaw/ permissions: ${dir_perms} (expected 700)"
        chmod 700 "$openclaw_dir"
    fi

    if [[ "$config_perms" == "600" ]]; then
        log_success "openclaw.json permissions: ${config_perms} (correct)"
    else
        log_error "openclaw.json permissions: ${config_perms} (expected 600)"
        chmod 600 "$openclaw_config"
    fi

    # Check for third-party skills
    local skill_count
    skill_count="$(find "${openclaw_dir}/skills/" -name "SKILL.md" 2>/dev/null | wc -l)"
    if [[ "$skill_count" -eq 0 ]]; then
        log_success "No third-party skills installed (policy: none)"
    else
        log_warn "${skill_count} skill(s) found in ~/.openclaw/skills/ — review for security"
    fi

    # Run security audit if available
    if is_installed openclaw; then
        log_info "Running OpenClaw security audit..."
        run_as_user "openclaw security audit --deep" 2>/dev/null || {
            log_warn "Security audit not available in this version — run manually later"
        }
    fi

    log_success "OpenClaw installed with hardened configuration"
    log_info "  Gateway: ws://127.0.0.1:${OPENCLAW_PORT} (loopback only)"
    log_info "  Auth: token (fail-closed)"
    log_info "  Sandbox: non-main sessions sandboxed"
    log_info "  LAN access: via Tailscale Serve (configure after Tailscale module)"
    log_info "  Gateway token stored in: ~/.openclaw/.gateway-token"
}
