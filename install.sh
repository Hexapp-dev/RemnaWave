#!/usr/bin/env bash

set -euo pipefail

# Remnawave full installer: Panel + Subscription Page + Nginx (SSL)
# Single prompt: panel domain (e.g., panel.example.com)

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

inplace_sed() {
  # Cross-distro sed -i
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

print_header() {
  echo ""
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

abort() {
  echo "Error: $1" >&2
  exit 1
}

print_banner() {
  local MAGENTA CYAN GRAY SEP BOLD RESET
  if [ -t 1 ]; then
    MAGENTA='\033[38;5;141m'  # muted orchid
    CYAN='\033[38;5;81m'     # soft teal
    GRAY='\033[38;5;245m'    # neutral gray text
    SEP='\033[38;5;244m'     # subtle separator
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
  echo -e "${GRAY} Installer: Remnawave Panel + Subscription + Nginx (SSL)${RESET}\n"
}

print_banner
print_header "Remnawave Automated Installer"

read -rp "Enter panel domain (e.g., panel.example.com): " PANEL_DOMAIN
PANEL_DOMAIN=${PANEL_DOMAIN// /}

[[ -z "$PANEL_DOMAIN" ]] && abort "Domain cannot be empty."
[[ "$PANEL_DOMAIN" =~ ^https?:// ]] && abort "Do not include http/https in the domain."

BASE_DIR=/opt/remnawave
NGINX_DIR=$BASE_DIR/nginx
SUB_DIR=$BASE_DIR/subscription
ENV_FILE=$BASE_DIR/.env

print_header "Installing prerequisites (curl, ca-certificates)"
if require_cmd apt-get; then
  sudo apt-get update -y
  sudo apt-get install -y curl ca-certificates
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
  # Ensure docker is running
  if require_cmd systemctl; then
    sudo systemctl enable --now docker || true
  fi
else
  echo "Docker already installed"
fi

print_header "Installing docker compose plugin (if needed)"
if ! docker compose version >/dev/null 2>&1; then
  if require_cmd apt-get; then
    sudo apt-get install -y docker-compose-plugin || true
  fi
fi
docker compose version >/dev/null 2>&1 || abort "Docker Compose plugin not available."

print_header "Installing acme.sh dependencies (cron, socat)"
if require_cmd apt-get; then
  sudo apt-get install -y cron socat
elif require_cmd dnf; then
  sudo dnf install -y cronie socat
elif require_cmd yum; then
  sudo yum install -y cronie socat
elif require_cmd pacman; then
  sudo pacman -Sy --noconfirm cronie socat
fi

print_header "Preparing directories"
ensure_dir "$BASE_DIR"
ensure_dir "$NGINX_DIR"
ensure_dir "$SUB_DIR"

print_header "Preparing subscription app-config.json"
# Prefer local repo file if present; otherwise fetch from GitHub
if [ -f "./app-config.json" ]; then
  cp -f ./app-config.json "$SUB_DIR/app-config.json"
elif [ ! -f "$SUB_DIR/app-config.json" ]; then
  curl -fsSL -o "$SUB_DIR/app-config.json" \
    https://raw.githubusercontent.com/Hexapp-dev/RemnaWave/refs/heads/main/app-config.json || true
fi

print_header "Downloading panel compose and env"
if [ ! -f "$BASE_DIR/docker-compose.yml" ]; then
  curl -fsSL -o "$BASE_DIR/docker-compose.yml" \
    https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml
else
  echo "docker-compose.yml already exists, keeping it"
fi

ENV_NEW=0
if [ ! -f "$ENV_FILE" ]; then
  curl -fsSL -o "$ENV_FILE" \
    https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample
  ENV_NEW=1
else
  echo ".env already exists, keeping it"
fi

print_header "Writing panel docker-compose.override.yml to use external network"
cat > "$BASE_DIR/docker-compose.override.yml" <<EOF
networks:
  remnawave-network:
    name: remnawave-network
    external: true
EOF

print_header "Generating secrets and configuring .env"
require_cmd openssl || abort "openssl is required"

# Secrets (generate ONLY on first install to avoid breaking existing installs)
if [ "$ENV_NEW" -eq 1 ]; then
  inplace_sed "s/^JWT_AUTH_SECRET=.*/JWT_AUTH_SECRET=$(openssl rand -hex 64)/" "$ENV_FILE"
  inplace_sed "s/^JWT_API_TOKENS_SECRET=.*/JWT_API_TOKENS_SECRET=$(openssl rand -hex 64)/" "$ENV_FILE"
  inplace_sed "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 64)/" "$ENV_FILE"
  inplace_sed "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)/" "$ENV_FILE"
else
  echo "Preserving existing JWT/metrics/webhook secrets in .env"
fi

# Postgres password and DATABASE_URL alignment
if [ "$ENV_NEW" -eq 1 ]; then
  POSTGRES_PASSWORD=$(openssl rand -hex 24)
  inplace_sed "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" "$ENV_FILE"
  inplace_sed "s|^DATABASE_URL=\"postgresql://postgres:[^@]*@|DATABASE_URL=\"postgresql://postgres:$POSTGRES_PASSWORD@|" "$ENV_FILE"
else
  echo "Preserving existing POSTGRES_PASSWORD and DATABASE_URL in .env"
fi

# Domains
if grep -q '^FRONT_END_DOMAIN=' "$ENV_FILE"; then
  inplace_sed "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=$PANEL_DOMAIN|" "$ENV_FILE"
else
  echo "FRONT_END_DOMAIN=$PANEL_DOMAIN" >> "$ENV_FILE"
fi

# For single-domain setup, expose subscription under /sub on the same domain
SUB_PUBLIC_DOMAIN_VALUE="$PANEL_DOMAIN/sub"
if grep -q '^SUB_PUBLIC_DOMAIN=' "$ENV_FILE"; then
  inplace_sed "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$SUB_PUBLIC_DOMAIN_VALUE|" "$ENV_FILE"
else
  echo "SUB_PUBLIC_DOMAIN=$SUB_PUBLIC_DOMAIN_VALUE" >> "$ENV_FILE"
fi

# Ensure DATABASE_URL includes schema=public
if grep -q '^DATABASE_URL=' "$ENV_FILE"; then
  if ! grep -q '^DATABASE_URL=.*schema=public' "$ENV_FILE"; then
    inplace_sed "s|^DATABASE_URL=\"\(postgresql://[^\"]*\)\"$|DATABASE_URL=\"\1?schema=public\"|" "$ENV_FILE" || true
  fi
fi

print_header "Creating external docker network if missing"
if ! docker network inspect remnawave-network >/dev/null 2>&1; then
  docker network create remnawave-network >/dev/null
fi

print_header "Starting Remnawave Panel"
(cd "$BASE_DIR" && docker compose up -d --force-recreate)

# Align Postgres password inside the DB with .env (idempotent, preserves data)
print_header "Aligning Postgres password with .env"
POSTGRES_PASSWORD_VALUE=$(grep '^POSTGRES_PASSWORD=' "$ENV_FILE" | cut -d'=' -f2-)
if docker ps --format '{{.Names}}' | grep -q '^remnawave-db$'; then
  # Wait until DB is healthy/ready
  for i in $(seq 1 60); do
    if docker exec -u postgres remnawave-db pg_isready -U postgres -d postgres -h 127.0.0.1 >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  # Attempt to set the password to the value from .env
  docker exec -u postgres remnawave-db bash -lc "psql -d postgres -c \"ALTER USER postgres WITH PASSWORD '$POSTGRES_PASSWORD_VALUE';\"" >/dev/null 2>&1 || true
  # Restart backend to pick up successful DB auth
  docker restart remnawave >/dev/null 2>&1 || true
fi

print_header "Installing acme.sh and issuing SSL cert for $PANEL_DOMAIN"
if [ ! -d "$HOME/.acme.sh" ]; then
  curl https://get.acme.sh | sh -s email=admin@$PANEL_DOMAIN
fi

# Ensure acme.sh in PATH without sourcing shell rc files (avoid PS1 issues under set -u)
export PATH="$HOME/.acme.sh:$PATH"
acme.sh --version >/dev/null 2>&1 || abort "acme.sh not found in PATH"

# Ensure cron service is running for auto-renew
if require_cmd systemctl; then
  sudo systemctl enable --now cron 2>/dev/null || sudo systemctl enable --now crond 2>/dev/null || true
fi

# Use Let's Encrypt as CA (instead of ZeroSSL/EAB)
acme.sh --set-default-ca --server letsencrypt || true

# Ensure target files exist directory-wise
ensure_dir "$NGINX_DIR"

# Tolerate any errors in the cert block and always continue
set +e
# Always fetch a fresh cert: purge old state and force issue
acme.sh --revoke -d "$PANEL_DOMAIN" >/dev/null 2>&1 || true
acme.sh --remove -d "$PANEL_DOMAIN" >/dev/null 2>&1 || true
rm -rf "$HOME/.acme.sh/$PANEL_DOMAIN" >/dev/null 2>&1 || true
rm -f "$NGINX_DIR/privkey.key" "$NGINX_DIR/fullchain.pem" >/dev/null 2>&1 || true

acme.sh --issue --standalone -d "$PANEL_DOMAIN" --alpn --tlsport 8443 --force || true

# Always install cert/key to target paths
acme.sh --install-cert -d "$PANEL_DOMAIN" \
  --key-file "$NGINX_DIR/privkey.key" \
  --fullchain-file "$NGINX_DIR/fullchain.pem" \
  --reloadcmd "cd $NGINX_DIR && docker compose restart remnawave-nginx || true" || true
set -e

print_header "SSL step finished, proceeding with Nginx and Subscription"

# Validate cert files; if invalid/missing, try copying from acme.sh store or create a temporary self-signed cert
if [ ! -s "$NGINX_DIR/fullchain.pem" ] || ! grep -q "BEGIN CERTIFICATE" "$NGINX_DIR/fullchain.pem" 2>/dev/null; then
  echo "fullchain.pem is missing/invalid. Attempting recovery..."
  SRC_CHAIN="$HOME/.acme.sh/$PANEL_DOMAIN/fullchain.cer"
  SRC_KEY="$HOME/.acme.sh/$PANEL_DOMAIN/$PANEL_DOMAIN.key"
  if [ -s "$SRC_CHAIN" ] && grep -q "BEGIN CERTIFICATE" "$SRC_CHAIN" 2>/dev/null && [ -s "$SRC_KEY" ]; then
    cp -f "$SRC_CHAIN" "$NGINX_DIR/fullchain.pem"
    cp -f "$SRC_KEY" "$NGINX_DIR/privkey.key"
    echo "Copied certs from acme.sh store."
  else
    echo "Acme certs not available. Generating temporary self-signed certificate."
    require_cmd openssl || abort "openssl is required to generate a temporary certificate"
    openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
      -keyout "$NGINX_DIR/privkey.key" \
      -out "$NGINX_DIR/fullchain.pem" \
      -subj "/CN=$PANEL_DOMAIN" >/dev/null 2>&1
  fi
fi

print_header "Writing Nginx configuration"
cat > "$NGINX_DIR/nginx.conf" <<'EOF'
upstream remnawave {
    server remnawave:3000;
}

upstream remnawave_subscription {
    server remnawave-subscription:3010;
}

server {
    server_name REPLACE_WITH_YOUR_DOMAIN;

    listen 443 ssl reuseport;
    listen [::]:443 ssl reuseport;
    http2 on;

    # Panel
    location / {
        proxy_http_version 1.1;
        proxy_pass http://remnawave;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
    }

    # Subscription page under /sub
    location /sub/ {
        proxy_http_version 1.1;
        # Preserve /sub prefix for the upstream (no trailing slash)
        proxy_pass http://remnawave_subscription;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # SSL Configuration (Mozilla Intermediate Guidelines)
    ssl_protocols          TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:DHE-RSA-CHACHA20-POLY1305;

    ssl_session_timeout 1d;
    ssl_session_cache shared:MozSSL:10m;
    ssl_session_tickets    off;
    ssl_certificate "/etc/nginx/ssl/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/privkey.key";
    ssl_trusted_certificate "/etc/nginx/ssl/fullchain.pem";

    ssl_stapling           on;
    ssl_stapling_verify    on;
    resolver               1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 208.67.222.222 208.67.220.220 valid=60s;
    resolver_timeout       2s;

    # Gzip Compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_min_length 256;
    gzip_types
        application/atom+xml
        application/geo+json
        application/javascript
        application/x-javascript
        application/json
        application/ld+json
        application/manifest+json
        application/rdf+xml
        application/rss+xml
        application/xhtml+xml
        application/xml
        font/eot
        font/otf
        font/ttf
        image/svg+xml
        text/css
        text/javascript
        text/plain
        text/xml;
}

server {
    listen 443 ssl default_server;
    listen [::]:443 ssl default_server;
    server_name _;

    ssl_reject_handshake on;
}
EOF

# Inject domain into nginx.conf
inplace_sed "s|REPLACE_WITH_YOUR_DOMAIN|$PANEL_DOMAIN|" "$NGINX_DIR/nginx.conf"

print_header "Writing Nginx docker-compose.yml"
cat > "$NGINX_DIR/docker-compose.yml" <<EOF
services:
  remnawave-nginx:
    image: nginx:1.28
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
      - ./fullchain.pem:/etc/nginx/ssl/fullchain.pem:ro
      - ./privkey.key:/etc/nginx/ssl/privkey.key:ro
    restart: always
    ports:
      - '0.0.0.0:443:443'
    networks:
      - remnawave-network

networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge
    external: true
EOF

print_header "Writing Subscription Page docker-compose.yml"
cat > "$SUB_DIR/docker-compose.yml" <<EOF
services:
  remnawave-subscription:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription
    environment:
      - REMNAWAVE_PANEL_URL=https://$PANEL_DOMAIN
      - APP_PORT=3010
      - META_TITLE="Subscription page"
      - META_DESCRIPTION="Subscription page for $PANEL_DOMAIN"
      - CUSTOM_SUB_PREFIX=sub
    restart: always
    ports:
      - '127.0.0.1:3010:3010'
    volumes:
      - './app-config.json:/opt/app/frontend/assets/app-config.json:ro'
    networks:
      - remnawave-network

networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge
    external: true
EOF

print_header "Starting Subscription Page"
(cd "$SUB_DIR" && docker compose up -d --force-recreate)

print_header "Starting Nginx"
(cd "$NGINX_DIR" && docker compose up -d --force-recreate)

echo ""
echo "All set! Installation completed successfully."
echo "Panel:        https://$PANEL_DOMAIN/"
echo "Subscription: https://$PANEL_DOMAIN/sub/"
echo "Note: Ensure DNS for $PANEL_DOMAIN points to this server and port 8443 was free during certificate issuance."


