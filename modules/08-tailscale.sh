#!/usr/bin/env bash
# =============================================================================
# 08-tailscale.sh — Tailscale for secure LAN access
# =============================================================================
# Installs Tailscale and walks through first-time setup including:
#   - Account creation guidance
#   - Interactive authentication (tailscale up)
#   - Tailscale Serve configuration for OpenClaw gateway
#   - Connectivity verification
#
# After this module completes on the Ubuntu machine, install Tailscale on
# your Windows PC (or other devices) to access OpenClaw securely.
# =============================================================================

_tailscale_first_time_guide() {
    echo ""
    echo -e "${BOLD}${CYAN}┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${CYAN}│           TAILSCALE FIRST-TIME SETUP GUIDE                   │${NC}"
    echo -e "${BOLD}${CYAN}├──────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${BOLD}${CYAN}│                                                              │${NC}"
    echo -e "${BOLD}${CYAN}│  Tailscale creates a private mesh network (\"tailnet\") so     │${NC}"
    echo -e "${BOLD}${CYAN}│  your devices can reach each other securely — no port        │${NC}"
    echo -e "${BOLD}${CYAN}│  forwarding, no firewall rules, auto-HTTPS.                  │${NC}"
    echo -e "${BOLD}${CYAN}│                                                              │${NC}"
    echo -e "${BOLD}${CYAN}│  STEP 1: Create a free Tailscale account                     │${NC}"
    echo -e "${BOLD}${CYAN}│    Go to: https://login.tailscale.com/start                  │${NC}"
    echo -e "${BOLD}${CYAN}│    Sign up with Google, Microsoft, GitHub, or email.          │${NC}"
    echo -e "${BOLD}${CYAN}│    Free tier supports 100 devices — more than enough.         │${NC}"
    echo -e "${BOLD}${CYAN}│                                                              │${NC}"
    echo -e "${BOLD}${CYAN}│  STEP 2: Authenticate THIS machine (next prompt)             │${NC}"
    echo -e "${BOLD}${CYAN}│    We'll run 'tailscale up' which prints a URL.               │${NC}"
    echo -e "${BOLD}${CYAN}│    Open that URL in any browser and log in.                   │${NC}"
    echo -e "${BOLD}${CYAN}│                                                              │${NC}"
    echo -e "${BOLD}${CYAN}│  STEP 3: Install Tailscale on your Windows PC                │${NC}"
    echo -e "${BOLD}${CYAN}│    Download from: https://tailscale.com/download/windows      │${NC}"
    echo -e "${BOLD}${CYAN}│    Sign in with the SAME account.                             │${NC}"
    echo -e "${BOLD}${CYAN}│    Both devices join a private network automatically.         │${NC}"
    echo -e "${BOLD}${CYAN}│                                                              │${NC}"
    echo -e "${BOLD}${CYAN}│  That's it — your devices can now see each other securely.    │${NC}"
    echo -e "${BOLD}${CYAN}└──────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

_tailscale_authenticate() {
    log_info "Starting Tailscale authentication..."
    echo ""
    echo -e "${BOLD}A URL will appear below. Open it in a browser to authenticate.${NC}"
    echo -e "${YELLOW}If this is a headless server, copy the URL to another device's browser.${NC}"
    echo ""

    # Run tailscale up interactively so the user sees the auth URL
    tailscale up

    # Verify authentication succeeded
    if tailscale status &>/dev/null; then
        local ts_ip ts_hostname
        ts_ip="$(tailscale ip -4 2>/dev/null || echo 'unknown')"
        ts_hostname="$(tailscale status --self --json 2>/dev/null | jq -r '.Self.HostName // "unknown"')"
        echo ""
        log_success "Tailscale authenticated!"
        log_info "  Tailscale IP:   ${ts_ip}"
        log_info "  Hostname:       ${ts_hostname}"
        log_info "  Tailnet name:   ${ts_hostname}.tail*.ts.net"
        return 0
    else
        log_error "Tailscale authentication failed or was cancelled"
        return 1
    fi
}

_tailscale_configure_serve() {
    log_info "Configuring Tailscale Serve for OpenClaw (port ${OPENCLAW_PORT})..."
    echo ""
    echo -e "  Tailscale Serve proxies ${BOLD}http://127.0.0.1:${OPENCLAW_PORT}${NC}"
    echo -e "  and makes it available as ${BOLD}https://<hostname>.<tailnet>.ts.net${NC}"
    echo -e "  with automatic HTTPS — only devices on your tailnet can reach it."
    echo ""

    if tailscale serve --bg "http://127.0.0.1:${OPENCLAW_PORT}" 2>/dev/null; then
        log_success "Tailscale Serve configured"

        # Show the serve status
        echo ""
        log_info "Tailscale Serve status:"
        tailscale serve status 2>/dev/null || true
        echo ""
    else
        log_warn "Tailscale Serve config failed — this is OK if OpenClaw isn't running yet"
        log_info "Run this manually after OpenClaw is started:"
        log_info "  sudo tailscale serve --bg http://127.0.0.1:${OPENCLAW_PORT}"
    fi
}

_tailscale_verify() {
    log_info "Running Tailscale connectivity verification..."
    echo ""

    local ts_ip ts_hostname all_good=true

    # Check 1: daemon running
    if is_service_active tailscaled; then
        echo -e "  ${GREEN}✓${NC} Tailscale daemon running"
    else
        echo -e "  ${RED}✗${NC} Tailscale daemon not running"
        all_good=false
    fi

    # Check 2: authenticated
    if tailscale status &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Authenticated to tailnet"
        ts_ip="$(tailscale ip -4 2>/dev/null || echo '')"
        ts_hostname="$(tailscale status --self --json 2>/dev/null | jq -r '.Self.HostName // ""')"
    else
        echo -e "  ${RED}✗${NC} Not authenticated (run: sudo tailscale up)"
        all_good=false
    fi

    # Check 3: has Tailscale IP
    if [[ -n "${ts_ip:-}" ]]; then
        echo -e "  ${GREEN}✓${NC} Tailscale IPv4: ${ts_ip}"
    else
        echo -e "  ${RED}✗${NC} No Tailscale IP assigned"
        all_good=false
    fi

    # Check 4: can reach self via Tailscale IP
    if [[ -n "${ts_ip:-}" ]] && ping -c 1 -W 2 "$ts_ip" &>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Self-ping via Tailscale IP: OK"
    elif [[ -n "${ts_ip:-}" ]]; then
        echo -e "  ${YELLOW}○${NC} Self-ping via Tailscale IP: no response (may be normal)"
    fi

    # Check 5: Tailscale Serve status
    if tailscale serve status 2>/dev/null | grep -q "${OPENCLAW_PORT}"; then
        echo -e "  ${GREEN}✓${NC} Tailscale Serve: proxying port ${OPENCLAW_PORT}"
    else
        echo -e "  ${YELLOW}○${NC} Tailscale Serve: not configured yet for port ${OPENCLAW_PORT}"
    fi

    # Check 6: other devices on tailnet
    local peer_count
    peer_count="$(tailscale status 2>/dev/null | grep -c 'offers\|active\|idle' || echo '0')"
    if [[ "$peer_count" -gt 0 ]]; then
        echo -e "  ${GREEN}✓${NC} Other devices on tailnet: ${peer_count}"
        echo ""
        log_info "  Tailnet peers:"
        tailscale status 2>/dev/null | grep -v "^$" | head -20 || true
    else
        echo -e "  ${YELLOW}○${NC} No other devices on tailnet yet"
        echo ""
        echo -e "  ${BOLD}To connect your Windows PC:${NC}"
        echo "    1. Download Tailscale: https://tailscale.com/download/windows"
        echo "    2. Install and sign in with the same account"
        echo "    3. Re-run: sudo ./setup.sh --test-tailscale"
    fi

    echo ""
    if $all_good; then
        log_success "Tailscale verification passed"
    else
        log_warn "Some checks failed — see above"
    fi
}

install_tailscale() {
    # --- Install ---
    if is_installed tailscale; then
        log_info "Tailscale already installed: $(tailscale version 2>/dev/null | head -1)"
    else
        log_info "Adding Tailscale apt repository..."
        curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg \
            | tee /usr/share/keyrings/tailscale-archive-keyring.gpg > /dev/null
        curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list \
            | tee /etc/apt/sources.list.d/tailscale.list > /dev/null

        log_info "Installing Tailscale..."
        apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tailscale
    fi

    # --- Start daemon ---
    if ! is_service_active tailscaled; then
        log_info "Starting Tailscale daemon..."
        systemctl enable tailscaled
        systemctl start tailscaled
    fi

    # --- Authenticate (interactive) ---
    if tailscale status &>/dev/null; then
        log_info "Tailscale already authenticated"
        log_info "  IP: $(tailscale ip -4 2>/dev/null || echo 'unknown')"
    else
        # First-time setup — show the guide
        _tailscale_first_time_guide

        read -rp "Do you have a Tailscale account ready? [Y/n] " has_account
        if [[ "${has_account,,}" == "n" ]]; then
            echo ""
            echo -e "${BOLD}Create an account at: https://login.tailscale.com/start${NC}"
            echo "Then re-run this script."
            echo ""
            log_warn "Tailscale installed but not authenticated — re-run setup.sh to continue"
            return 0
        fi

        _tailscale_authenticate || {
            log_warn "Skipping Tailscale auth — re-run setup.sh to try again"
            return 0
        }
    fi

    # --- Configure Serve ---
    _tailscale_configure_serve

    # --- Verify ---
    _tailscale_verify

    # --- Windows instructions ---
    echo ""
    echo -e "${BOLD}${CYAN}┌──────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${BOLD}${CYAN}│           WINDOWS PC SETUP                                   │${NC}"
    echo -e "${BOLD}${CYAN}├──────────────────────────────────────────────────────────────┤${NC}"
    echo -e "${BOLD}${CYAN}│                                                              │${NC}"
    echo -e "${BOLD}${CYAN}│  1. Download: https://tailscale.com/download/windows          │${NC}"
    echo -e "${BOLD}${CYAN}│  2. Install the .exe and sign in with the SAME account        │${NC}"
    echo -e "${BOLD}${CYAN}│  3. Both machines appear in Tailscale admin console:          │${NC}"
    echo -e "${BOLD}${CYAN}│     https://login.tailscale.com/admin/machines                │${NC}"
    echo -e "${BOLD}${CYAN}│                                                              │${NC}"
    echo -e "${BOLD}${CYAN}│  Once connected, access OpenClaw from Windows via:            │${NC}"
    echo -e "${BOLD}${CYAN}│    https://$(tailscale status --self --json 2>/dev/null | jq -r '.Self.DNSName // "<hostname>.tail*.ts.net"' | sed 's/\.$//')${NC}"
    echo -e "${BOLD}${CYAN}│                                                              │${NC}"
    echo -e "${BOLD}${CYAN}│  Test connectivity from Windows PowerShell:                   │${NC}"
    echo -e "${BOLD}${CYAN}│    tailscale ping $(tailscale status --self --json 2>/dev/null | jq -r '.Self.HostName // "<this-hostname>"')${NC}"
    echo -e "${BOLD}${CYAN}│                                                              │${NC}"
    echo -e "${BOLD}${CYAN}└──────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    log_success "Tailscale module complete"
}
