# Ubuntu 24.04 Bulletproof Setup Script

A modular, idempotent setup script that takes a fresh Ubuntu 24.04 install to a fully operational AI/LLM workstation with NVIDIA GPU support, Docker, and security-hardened OpenClaw.

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/danmartinez78/openclaw_setup.git
cd openclaw_setup

# 2. Create your config from the template
cp config.env.example config.env
nano config.env          # Set API keys and preferences

# 3. Run the setup
sudo ./setup.sh

# 4. Reboot when prompted (NVIDIA driver needs it)
# 5. Re-run after reboot — the script resumes automatically
sudo ./setup.sh
```

## What Gets Installed

| Component | Purpose | Module |
|-----------|---------|--------|
| **System base** | build-essential, git, curl, htop, tmux, etc. | `01-system-base` |
| **NVIDIA Driver + CUDA** | Full GPU compute support | `02-nvidia-driver` |
| **Docker Engine** | Container runtime (official repo) | `03-docker` |
| **NVIDIA Container Toolkit** | GPU access from Docker containers | `04-nvidia-container` |
| **Ollama** | Local LLM server with GPU auto-detection | `05-ollama` |
| **Node.js 22** | Required by OpenClaw | `06-node` |
| **OpenClaw** | AI assistant (security-hardened) | `07-openclaw` |
| **Tailscale** | Secure LAN access via auto-HTTPS | `08-tailscale` |
| **llmfit** | Hardware-aware LLM model recommender | `09-llmfit` |
| **vLLM** | Production LLM serving (Docker + GPU) | `10-vllm` |
| **VS Code** | Code editor | `11-vscode` |
| **Terminator** | Tiling terminal emulator | `12-terminator` |
| **NoMachine** | Remote desktop (NX protocol) | `13-nomachine` |
| **Portainer** | Docker web UI | `14-portainer` |
| **GPU Monitoring** | nvtop + gpustat | `15-gpu-monitoring` |
| **Python uv** | Fast Python package manager | `16-python-uv` |

## Configuration

Edit `config.env` before running. Key settings:

```bash
# Skip components you don't need
INSTALL_VLLM=false
INSTALL_NOMACHINE=false

# vLLM — which GPU and model to use
VLLM_GPU_DEVICE=0                    # GPU index (nvidia-smi order)
VLLM_DEFAULT_MODEL="Qwen/Qwen3-0.6B"
HF_TOKEN="hf_..."                   # For gated models

# NoMachine version (no stable "latest" URL)
NOMACHINE_VERSION="8.14.2_1"
```

## Script Features

- **Idempotent** — safe to re-run at any time; already-installed components are skipped
- **Checkpoint system** — tracks progress in `.checkpoint`; resumes after reboot
- **Feature flags** — skip any component by setting `INSTALL_<NAME>=false` in `config.env`
- **Logging** — all output logged to `setup.log` with timestamps

```bash
# Check what's been installed
sudo ./setup.sh --status

# Reset checkpoints to re-run from scratch
sudo ./setup.sh --reset
```

## Security Architecture

### OpenClaw Hardening

The setup script applies a security-first OpenClaw configuration:

| Layer | Setting | Effect |
|-------|---------|--------|
| **Network** | `gateway.bind: "loopback"` | Gateway only on 127.0.0.1 |
| **LAN access** | `tailscale.mode: "serve"` | Auto-HTTPS via Tailscale — never raw on network |
| **Auth** | `auth.mode: "token"` | Fail-closed; auto-generated 256-bit token |
| **Discovery** | `mdns.mode: "off"` | No network info disclosure |
| **Sandboxing** | `sandbox.mode: "non-main"` | Non-owner sessions run in Docker containers |
| **File access** | `fs.workspaceOnly: true` | Agent restricted to workspace directory |
| **DM isolation** | `dmScope: "per-channel-peer"` | Sessions isolated per channel/peer |
| **Skills** | None installed | No third-party skills — agent uses host tools via `exec` |
| **Permissions** | `~/.openclaw/` = 700, `openclaw.json` = 600 | User-only access |

### No Third-Party Skills Policy

Skills can direct the agent to execute arbitrary commands. This setup installs **zero** third-party skills. The agent accesses host tools (llmfit, nvidia-smi, etc.) via `exec` in the main session, which runs directly on the host since `sandbox.mode` is `"non-main"`.

### Service Binding

All services bind to `127.0.0.1` only:

| Service | Port | Access Method |
|---------|------|---------------|
| OpenClaw Gateway | 18789 | Tailscale Serve (auto-HTTPS) |
| vLLM API | 8000 | Tailscale or SSH tunnel |
| Portainer | 9443 | Tailscale or SSH tunnel |
| Ollama | 11434 | localhost only |

### Gateway Token

The setup auto-generates a 256-bit gateway token stored at `~/.openclaw/.gateway-token` (permissions 600). This token is required for all WebSocket connections to the gateway.

## Multi-GPU Notes

This setup is designed for mixed NVIDIA GPUs (e.g., 4070 Ti + 3080 + 3060 Ti + 2080 Ti).

**Key constraints:**
- **Tensor parallelism across mixed GPUs is NOT supported** — different compute capabilities (8.9, 8.6, 7.5) prevent it
- **vLLM** is pinned to a single GPU via `CUDA_VISIBLE_DEVICES` in its docker-compose.yml
- **Ollama** handles mixed GPUs better and can split large models across GPUs automatically
- Use `nvtop` to monitor per-GPU utilization

**To run multiple vLLM instances** (one per GPU, different models), duplicate the service in `~/vllm/docker-compose.yml`:

```yaml
services:
  vllm-gpu0:
    # ... same as vllm but with:
    environment:
      - CUDA_VISIBLE_DEVICES=0
    ports:
      - "127.0.0.1:8000:8000"
    command: ["--model", "Qwen/Qwen3-8B"]

  vllm-gpu1:
    # ... same as vllm but with:
    environment:
      - CUDA_VISIBLE_DEVICES=1
    ports:
      - "127.0.0.1:8001:8000"
    command: ["--model", "microsoft/phi-3-mini-4k-instruct"]
```

## API Provider Configuration

OpenClaw is pre-configured for three API providers. Set your keys in `config.env` before running the script, or edit `~/.openclaw/.env` afterwards.

| Provider | Env Variable | Model Prefix | Notes |
|----------|-------------|--------------|-------|
| **Z.ai** | `ZAI_API_KEY` | `zai/` | Built-in provider |
| **Gemini** | `GEMINI_API_KEY` | `google/` | Built-in provider |
| **Haimaker** | `HAIMAKER_API_KEY` + `HAIMAKER_BASE_URL` | `haimaker/` | Custom provider (OpenAI-compatible) |

### Setting API keys

**Option A** — in `config.env` before setup:
```bash
ZAI_API_KEY="your-key-here"
GEMINI_API_KEY="your-key-here"
HAIMAKER_API_KEY="your-key-here"
HAIMAKER_BASE_URL="https://api.haimaker.example/v1"
```

**Option B** — edit `~/.openclaw/.env` after setup:
```bash
nano ~/.openclaw/.env
# Add or update keys, then restart OpenClaw
openclaw restart
```

### Model routing

Set a primary model and fallbacks in `config.env`:
```bash
OPENCLAW_PRIMARY_MODEL="zai/glm-4.7"
OPENCLAW_FALLBACK_MODELS="google/gemini-3-pro-preview,haimaker/your-model"
```

Leave blank to use OpenClaw's defaults. You can also change model routing later in `~/.openclaw/openclaw.json`.

## Agent Migration

To transfer your agent identity (SOUL.md, AGENTS.md, etc.) from an existing OpenClaw install:

### Step 1: Export from the source machine

```bash
# On the machine with your existing OpenClaw:
tar czf openclaw-backup.tar.gz -C ~/ .openclaw/workspace/

# Transfer to the new machine (via USB, scp, etc.):
scp openclaw-backup.tar.gz user@new-machine:/tmp/
```

### Step 2: Set the migration path

In `config.env` on the new machine:
```bash
OPENCLAW_MIGRATE_FROM="/tmp/openclaw-backup.tar.gz"
```

Or point to a directory:
```bash
OPENCLAW_MIGRATE_FROM="/mnt/usb/openclaw-backup/"
```

### Step 3: Run setup

The script will:
1. Extract and copy workspace files (SOUL.md, AGENTS.md, USER.md, IDENTITY.md, TOOLS.md, memory/, etc.)
2. Set `skipBootstrap: true` so OpenClaw doesn't overwrite your transferred files
3. Fix file ownership and permissions

### Migrated files

| File | Purpose |
|------|---------|
| `SOUL.md` | Agent persona and core identity |
| `AGENTS.md` | Agent instructions and behavior rules |
| `USER.md` | User information and preferences |
| `IDENTITY.md` | Name, emoji, vibe |
| `TOOLS.md` | Tool usage preferences |
| `HEARTBEAT.md` | Periodic check-in config |
| `BOOT.md` | Bootstrap sequence |
| `memory/` | Agent memory entries |

## Post-Install Steps

1. **Authenticate Tailscale** (the script walks you through this interactively)
2. **Install Tailscale on Windows**: Download from https://tailscale.com/download/windows, sign in with the same account
3. **Test connectivity**: `sudo ./setup.sh --test-tailscale`
4. **Configure Tailscale Serve**: `sudo tailscale serve --bg http://127.0.0.1:18789`
5. **Set up API keys**: Edit `config.env` or `~/.openclaw/.env` (see API Provider Configuration above)
6. **Pull an Ollama model**: `ollama pull llama3.2:3b`
7. **Start vLLM** (if needed): `sudo systemctl start vllm`
8. **Set up Portainer admin**: Visit `https://127.0.0.1:9443`
9. **Run security audit**: `openclaw security audit --deep`

## Tailscale Setup (First-Time Guide)

Tailscale creates a private mesh network ("tailnet") so your devices can securely reach each other — no port forwarding, no firewall holes, automatic HTTPS certificates.

### On the Ubuntu machine (handled by setup.sh)

The setup script walks you through this interactively:
1. Creates a Tailscale account (free tier, 100 devices)
2. Authenticates the machine (`tailscale up` → opens a URL)
3. Configures Tailscale Serve to proxy OpenClaw with auto-HTTPS

### On your Windows PC

1. **Download**: https://tailscale.com/download/windows
2. **Install** the `.exe` and sign in with the **same account**
3. Both machines automatically appear on your private tailnet

### Verify connectivity

```bash
# On the Ubuntu box — run the built-in test:
sudo ./setup.sh --test-tailscale

# From Windows PowerShell — ping the Ubuntu box:
tailscale ping <ubuntu-hostname>

# From Windows browser — access OpenClaw:
# https://<ubuntu-hostname>.<tailnet>.ts.net
```

### Tailscale admin console

View all your devices, manage access, and revoke keys at:
https://login.tailscale.com/admin/machines

### How Tailscale Serve works

```
Windows PC (browser)
    │
    └─ HTTPS ──▶ Tailscale Serve (auto-HTTPS on tailnet)
                     │
                     └─ HTTP ──▶ 127.0.0.1:18789 (OpenClaw gateway)
```

The OpenClaw gateway **never** listens on a real network interface. Tailscale Serve accepts HTTPS connections from your tailnet and proxies them to localhost. Only devices signed into your Tailscale account can reach it.

## Troubleshooting

### NVIDIA driver not loading after reboot
```bash
# Check if modules are loaded
lsmod | grep nvidia
# Check dkms status
dkms status
# Reinstall if needed
sudo apt install --reinstall cuda
```

### Docker GPU access fails
```bash
# Verify NVIDIA Container Toolkit
nvidia-ctk --version
# Reconfigure and restart
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
# Test
docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu24.04 nvidia-smi
```

### OpenClaw won't start
```bash
# Check daemon status
openclaw doctor
# Check logs
journalctl --user -u openclaw -f
# Verify config
cat ~/.openclaw/openclaw.json | jq .
# Run security audit
openclaw security audit --deep
```

### vLLM out of memory
```bash
# Check which GPU has enough VRAM
nvidia-smi
# Use a smaller model or different GPU in ~/vllm/.env
VLLM_MODEL=Qwen/Qwen3-0.6B
```

## License

MIT
