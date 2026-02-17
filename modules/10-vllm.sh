#!/usr/bin/env bash
# =============================================================================
# 10-vllm.sh — vLLM via Docker with GPU passthrough
# =============================================================================
# Deploys vLLM using the official Docker image with NVIDIA GPU support.
# Creates a docker-compose.yml and a systemd service for persistent operation.
#
# IMPORTANT: Mixed GPUs (4070 Ti + 3080 + 3060 Ti + 2080 Ti) do NOT support
# tensor parallelism. vLLM is pinned to a single GPU via CUDA_VISIBLE_DEVICES
# (configurable in config.env as VLLM_GPU_DEVICE).
# =============================================================================

install_vllm() {
    if ! is_installed docker; then
        log_error "Docker required. Run module 03-docker first."
        return 1
    fi

    local vllm_dir="${REAL_HOME}/vllm"

    # Create vLLM directory
    run_as_user "mkdir -p '${vllm_dir}'"

    # Create docker-compose.yml
    log_info "Writing vLLM docker-compose.yml..."
    cat > "${vllm_dir}/docker-compose.yml" << VLLM_COMPOSE
services:
  vllm:
    image: vllm/vllm-openai:latest
    container_name: vllm
    runtime: nvidia
    restart: unless-stopped
    ports:
      - "127.0.0.1:${VLLM_PORT}:8000"
    volumes:
      - "\${HOME}/.cache/huggingface:/root/.cache/huggingface"
    environment:
      - CUDA_VISIBLE_DEVICES=${VLLM_GPU_DEVICE}
      - HF_TOKEN=\${HF_TOKEN:-}
      - VLLM_USAGE_STATS=0
    ipc: host
    command:
      - "--model"
      - "\${VLLM_MODEL:-${VLLM_DEFAULT_MODEL}}"
      - "--host"
      - "0.0.0.0"
      - "--port"
      - "8000"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              device_ids: ["${VLLM_GPU_DEVICE}"]
              capabilities: [gpu]
VLLM_COMPOSE

    chown "${REAL_USER}:${REAL_USER}" "${vllm_dir}/docker-compose.yml"

    # Create .env file for docker-compose
    cat > "${vllm_dir}/.env" << VLLM_ENV
# vLLM environment — edit these values as needed
VLLM_MODEL=${VLLM_DEFAULT_MODEL}
HF_TOKEN=${HF_TOKEN}
VLLM_ENV

    chown "${REAL_USER}:${REAL_USER}" "${vllm_dir}/.env"
    chmod 600 "${vllm_dir}/.env"

    # Create HuggingFace cache directory
    run_as_user "mkdir -p '${REAL_HOME}/.cache/huggingface'"

    # Pull the image
    log_info "Pulling vLLM Docker image (this may take a while)..."
    docker pull vllm/vllm-openai:latest

    # Create systemd service for auto-start
    log_info "Creating vLLM systemd service..."
    cat > /etc/systemd/system/vllm.service << VLLM_SERVICE
[Unit]
Description=vLLM OpenAI-compatible API server
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=${REAL_USER}
WorkingDirectory=${vllm_dir}
ExecStartPre=/usr/bin/docker compose pull --quiet
ExecStart=/usr/bin/docker compose up --remove-orphans
ExecStop=/usr/bin/docker compose down
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
VLLM_SERVICE

    systemctl daemon-reload
    systemctl enable vllm

    log_success "vLLM configured"
    log_info "  Compose file: ${vllm_dir}/docker-compose.yml"
    log_info "  API endpoint: http://127.0.0.1:${VLLM_PORT}/v1 (loopback only)"
    log_info "  Default model: ${VLLM_DEFAULT_MODEL}"
    log_info "  GPU device: ${VLLM_GPU_DEVICE}"
    log_info "  Start: sudo systemctl start vllm"
    log_info "  Logs:  journalctl -u vllm -f"
    log_warn "vLLM service NOT auto-started (may need HF_TOKEN for some models)"
    log_info "  To start: sudo systemctl start vllm"
    log_info "  To change model: edit ${vllm_dir}/.env and restart"
}
