#!/usr/bin/env bash

set -euo pipefail

# Remnawave Panel Installer
# Following the official installation steps

clear_screen() {
  if command -v tput >/dev/null 2>&1; then
    tput reset || printf '\033c'
  elif command -v clear >/dev/null 2>&1; then
    clear
  else
    printf '\033[2J\033[H'
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
  echo -e "${GRAY} Installer: Remnawave Panel${RESET}\n"
}

print_banner
print_header "Remnawave Panel Installer"

# Get domain from user
read -rp "Enter your panel domain (e.g., panel.yourdomain.com): " FRONT_END_DOMAIN
FRONT_END_DOMAIN=${FRONT_END_DOMAIN// /}

if [ -z "$FRONT_END_DOMAIN" ]; then
  echo "Error: Panel domain cannot be empty." >&2
  exit 1
fi

# Calculate SUB_PUBLIC_DOMAIN
SUB_PUBLIC_DOMAIN="${FRONT_END_DOMAIN}/api/sub"

print_header "Installing Docker"
echo "Installing Docker if not installed yet..."
sudo curl -fsSL https://get.docker.com | sh

print_header "Step 1 – Download required files"
echo "Creating project directory..."
mkdir -p /opt/remnawave && cd /opt/remnawave

echo "Downloading docker-compose.yml..."
curl -o docker-compose.yml https://github.com/remnawave/backend/raw/refs/heads/main/docker-compose-prod.yml

echo "Downloading .env file..."
curl -o .env https://github.com/remnawave/backend/raw/refs/heads/main/.env.sample

print_header "Step 2 – Configure the .env file"
echo "Generating secure keys..."

# Generate JWT secrets
sed -i "s/^JWT_AUTH_SECRET=.*/JWT_AUTH_SECRET=$(openssl rand -hex 64)/" .env
sed -i "s/^JWT_API_TOKENS_SECRET=.*/JWT_API_TOKENS_SECRET=$(openssl rand -hex 64)/" .env

# Generate passwords
sed -i "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 64)/" .env
sed -i "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)/" .env

# Change Postgres password
echo "Generating Postgres password..."
pw=$(openssl rand -hex 24)
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$pw/" .env
sed -i "s|^\(DATABASE_URL=\"postgresql://postgres:\)[^@]*\(@.*\)|\1$pw\2|" .env

# Update domain variables
echo "Configuring domain settings..."
sed -i "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=$FRONT_END_DOMAIN|" .env
sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$SUB_PUBLIC_DOMAIN|" .env

print_header "Step 3 – Start the containers"
echo "Starting the containers..."
docker compose up -d && docker compose logs -f -t

echo ""
echo "============================================================"
echo "Installation completed successfully!"
echo "============================================================"
echo "Panel URL: https://$FRONT_END_DOMAIN"
echo "Subscription URL: https://$SUB_PUBLIC_DOMAIN"
echo ""
echo "Note: Make sure your domain DNS points to this server."
echo "============================================================"
