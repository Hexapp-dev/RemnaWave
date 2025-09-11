#!/usr/bin/env bash

set -euo pipefail

# Remnawave Node installer (Xray node)
# Style aligned with install.sh (banner, colors, headers)

clear_screen() {
  if command -v tput >/dev/null 2>&1; then
    tput reset || printf '\033c'
  elif command -v clear >/dev/null 2>&1; then
    clear
  else
    printf '\033[2J\033[H'
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

ensure_dir() {
  local d="$1"
  if [ ! -d "$d" ]; then
    mkdir -p "$d"
  fi
}

print_header() {
  echo ""
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

print_banner() {
  local MAGENTA CYAN GRAY SEP BOLD RESET
  if [ -t 1 ]; then
    MAGENTA='\033[38;5;141m'
    CYAN='\033[38;5;81m'
    GRAY='\033[38;5;245m'
    SEP='\033[38;5;244m'
    BOLD='\033[1m'
    RESET='\033[0m'
  else
    MAGENTA=''; CYAN=''; GRAY=''; SEP=''; BOLD=''; RESET=''
  fi

  clear_screen
  echo ""
  echo -e "${SEP}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${SEP}║                                                          ║${RESET}"
  echo -e "${SEP}║   ${MAGENTA}${BOLD}██╗  ██╗███████╗██╗  ██╗  ${CYAN}  █████╗ ██████╗ ██████╗     ${SEP}║${RESET}"
  echo -e "${SEP}║   ${MAGENTA}${BOLD}██║  ██║██╔════╝╚██╗██╔╝  ${CYAN} ██╔══██╗██╔══██╗██╔══██╗    ${SEP}║${RESET}"
  echo -e "${SEP}║   ${MAGENTA}${BOLD}███████║█████╗   ╚███╔╝   ${CYAN} ███████║██████╔╝██████╔╝    ${SEP}║${RESET}"
  echo -e "${SEP}║   ${MAGENTA}${BOLD}██╔══██║██╔══╝   ██╔██╗   ${CYAN} ██╔══██║██╔═══╝ ██╔═══╝     ${SEP}║${RESET}"
  echo -e "${SEP}║   ${MAGENTA}${BOLD}██║  ██║███████╗██╔╝ ██╗  ${CYAN} ██║  ██║██║     ██║         ${SEP}║${RESET}"
  echo -e "${SEP}║   ${MAGENTA}${BOLD}╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝  ${CYAN} ╚═╝  ╚═╝╚═╝     ╚═╝         ${SEP}║${RESET}"
  echo -e "${SEP}║                                                          ║${RESET}"
  echo -e "${SEP}╚══════════════════════════════════════════════════════════╝${RESET}"
  echo -e "${GRAY} Website: https://hexapp.dev${RESET}"
  echo -e "${GRAY} Installer: Remnawave Node (Xray)${RESET}\n"
}

print_banner
print_header "Remnawave Node Installer"

BASE_DIR=/opt/remnanode
ENV_FILE=$BASE_DIR/.env
COMPOSE_FILE=$BASE_DIR/docker-compose.yml

# Inputs
read -rp "Enter Node APP_PORT (default 2222): " APP_PORT
APP_PORT=${APP_PORT// /}
if [ -z "${APP_PORT:-}" ]; then APP_PORT=2222; fi

echo "Paste SSL_CERT line as copied from Panel (starts with SSL_CERT=):"
read -r SSL_CERT_INPUT

if [ -z "${SSL_CERT_INPUT:-}" ]; then
  echo "Error: SSL_CERT is required. Open Panel → Nodes → + (Create) → copy from Important note." >&2
  exit 1
fi

# Normalize SSL_CERT line
if ! echo "$SSL_CERT_INPUT" | grep -q '^SSL_CERT='; then
  SSL_CERT_INPUT="SSL_CERT=$SSL_CERT_INPUT"
fi

print_header "Installing prerequisites (curl, ca-certificates)"
if require_cmd apt-get; then
  sudo dpkg --configure -a >/dev/null 2>&1 || true
  sudo apt-get update -y
  sudo apt-get install -y curl ca-certificates || { sudo dpkg --configure -a || true; sudo apt-get install -y curl ca-certificates; }
elif require_cmd dnf; then
  sudo dnf install -y curl ca-certificates
elif require_cmd yum; then
  sudo yum install -y curl ca-certificates
elif require_cmd pacman; then
  sudo pacman -Sy --noconfirm curl ca-certificates
fi

print_header "Installing Docker"
if ! require_cmd docker; then
  curl -fsSL https://get.docker.com | sh
  if require_cmd systemctl; then
    sudo systemctl enable --now docker || true
  fi
else
  echo "Docker already installed"
fi

print_header "Preparing directories"
ensure_dir "$BASE_DIR"

print_header "Writing .env (idempotent)"
if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<EOF
APP_PORT=$APP_PORT
$SSL_CERT_INPUT
EOF
  echo ".env created"
else
  # Update APP_PORT if different
  if grep -q '^APP_PORT=' "$ENV_FILE"; then
    sed -i "s|^APP_PORT=.*|APP_PORT=$APP_PORT|" "$ENV_FILE"
  else
    echo "APP_PORT=$APP_PORT" >> "$ENV_FILE"
  fi
  # Update or append SSL_CERT
  if grep -q '^SSL_CERT=' "$ENV_FILE"; then
    sed -i "s|^SSL_CERT=.*|$SSL_CERT_INPUT|" "$ENV_FILE"
  else
    echo "$SSL_CERT_INPUT" >> "$ENV_FILE"
  fi
  echo ".env updated"
fi

print_header "Writing docker-compose.yml"
cat > "$COMPOSE_FILE" <<'EOF'
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:latest
    restart: always
    network_mode: host
    env_file:
      - .env
EOF

print_header "Starting Remnawave Node"
(cd "$BASE_DIR" && docker compose up -d --force-recreate)

echo ""
echo "All set! Remnawave Node installed successfully."
echo "Node runs on host network. Ensure firewall allows APP_PORT from your Panel's routing."
echo "Config: $BASE_DIR/.env  |  Compose: $BASE_DIR/docker-compose.yml"
echo "Docs: https://remna.st/docs/install/remnawave-node"


