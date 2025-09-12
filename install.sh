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
  echo -e "${SEP}╔═════════════════════════════════════════════════════════╗${RESET}"
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

read -rp "Enter subscription domain (e.g., sub.example.com): " SUB_DOMAIN
SUB_DOMAIN=${SUB_DOMAIN// /}

[[ -z "$PANEL_DOMAIN" ]] && abort "Panel domain cannot be empty."
[[ -z "$SUB_DOMAIN" ]] && abort "Subscription domain cannot be empty."
[[ "$PANEL_DOMAIN" =~ ^https?:// ]] && abort "Do not include http/https in the panel domain."
[[ "$SUB_DOMAIN" =~ ^https?:// ]] && abort "Do not include http/https in the subscription domain."

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

# Check if domains have changed and reset secrets if needed
CURRENT_PANEL_DOMAIN=$(grep '^FRONT_END_DOMAIN=' "$ENV_FILE" | cut -d'=' -f2- 2>/dev/null || echo "")
CURRENT_SUB_DOMAIN=$(grep '^SUB_PUBLIC_DOMAIN=' "$ENV_FILE" | cut -d'=' -f2- 2>/dev/null || echo "")

if [ "$CURRENT_PANEL_DOMAIN" != "$PANEL_DOMAIN" ] || [ "$CURRENT_SUB_DOMAIN" != "$SUB_DOMAIN" ]; then
  echo "Domain configuration changed. Regenerating secrets to ensure compatibility..."
  inplace_sed "s/^JWT_AUTH_SECRET=.*/JWT_AUTH_SECRET=$(openssl rand -hex 64)/" "$ENV_FILE"
  inplace_sed "s/^JWT_API_TOKENS_SECRET=.*/JWT_API_TOKENS_SECRET=$(openssl rand -hex 64)/" "$ENV_FILE"
  inplace_sed "s/^METRICS_PASS=.*/METRICS_PASS=$(openssl rand -hex 64)/" "$ENV_FILE"
  inplace_sed "s/^WEBHOOK_SECRET_HEADER=.*/WEBHOOK_SECRET_HEADER=$(openssl rand -hex 64)/" "$ENV_FILE"
  echo "Secrets regenerated for new domain configuration."
fi

# Postgres password and DATABASE_URL alignment
if [ "$ENV_NEW" -eq 1 ]; then
  POSTGRES_PASSWORD=$(openssl rand -hex 24)
  inplace_sed "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" "$ENV_FILE"
  inplace_sed "s|^DATABASE_URL=\"postgresql://postgres:[^@]*@|DATABASE_URL=\"postgresql://postgres:$POSTGRES_PASSWORD@|" "$ENV_FILE"
else
  echo "Preserving existing POSTGRES_PASSWORD and DATABASE_URL in .env"
fi

# Reset Postgres password if domains changed
if [ "$CURRENT_PANEL_DOMAIN" != "$PANEL_DOMAIN" ] || [ "$CURRENT_SUB_DOMAIN" != "$SUB_DOMAIN" ]; then
  echo "Regenerating Postgres password for new domain configuration..."
  POSTGRES_PASSWORD=$(openssl rand -hex 24)
  inplace_sed "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$POSTGRES_PASSWORD/" "$ENV_FILE"
  inplace_sed "s|^DATABASE_URL=\"postgresql://postgres:[^@]*@|DATABASE_URL=\"postgresql://postgres:$POSTGRES_PASSWORD@|" "$ENV_FILE"
  echo "Postgres password regenerated for new domain configuration."
fi

# Domains
if grep -q '^FRONT_END_DOMAIN=' "$ENV_FILE"; then
  inplace_sed "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=$PANEL_DOMAIN|" "$ENV_FILE"
else
  echo "FRONT_END_DOMAIN=$PANEL_DOMAIN" >> "$ENV_FILE"
fi

# Expose subscription on a separate domain (no scheme)
SUB_PUBLIC_DOMAIN_VALUE="$SUB_DOMAIN"
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

print_header "Installing acme.sh and issuing SSL certificates"
install_acme_sh() {
  if [ ! -d "$HOME/.acme.sh" ]; then
    curl -fsSL https://get.acme.sh | sh -s email=admin@$PANEL_DOMAIN
  fi
  
  export PATH="$HOME/.acme.sh:$PATH"
  acme.sh --version >/dev/null 2>&1 || abort "acme.sh not found in PATH"
  
  # Ensure cron service is running for auto-renew
  if require_cmd systemctl; then
    sudo systemctl enable --now cron 2>/dev/null || sudo systemctl enable --now crond 2>/dev/null || true
  fi
  
  # Use Let's Encrypt as CA
  acme.sh --set-default-ca --server letsencrypt || true
}

issue_certificate() {
  local domain="$1"
  local cert_dir="$2"
  
  echo "Issuing certificate for $domain..."
  
  # Clean up any existing certificates
  acme.sh --revoke -d "$domain" >/dev/null 2>&1 || true
  acme.sh --remove -d "$domain" >/dev/null 2>&1 || true
  rm -rf "$HOME/.acme.sh/$domain" >/dev/null 2>&1 || true
  rm -rf "$HOME/.acme.sh/${domain}_ecc" >/dev/null 2>&1 || true
  
  # Issue new certificate
  if acme.sh --issue --standalone -d "$domain" --alpn --tlsport 8443 --force; then
    echo "✓ Certificate issued successfully for $domain"
    
    # Install certificate to target directory
    if acme.sh --install-cert -d "$domain" \
      --key-file "$cert_dir/privkey.pem" \
      --fullchain-file "$cert_dir/fullchain.pem" \
      --reloadcmd "echo 'Certificate installed for $domain'" >/dev/null 2>&1; then
      echo "✓ Certificate installed for $domain"
    else
      echo "⚠ Failed to install certificate for $domain, copying manually..."
      copy_cert_from_acme "$domain" "$cert_dir"
    fi
  else
    echo "⚠ Failed to issue certificate for $domain, generating self-signed..."
    generate_self_signed_cert "$domain" "$cert_dir"
  fi
}

copy_cert_from_acme() {
  local domain="$1"
  local cert_dir="$2"
  
  # Try ECC first, then regular
  local src_chain="$HOME/.acme.sh/${domain}_ecc/fullchain.cer"
  local src_key="$HOME/.acme.sh/${domain}_ecc/$domain.key"
  
  if [ ! -s "$src_chain" ] || [ ! -s "$src_key" ]; then
    src_chain="$HOME/.acme.sh/$domain/fullchain.cer"
    src_key="$HOME/.acme.sh/$domain/$domain.key"
  fi
  
  if [ -s "$src_chain" ] && [ -s "$src_key" ] && grep -q "BEGIN CERTIFICATE" "$src_chain" 2>/dev/null; then
    cp -f "$src_chain" "$cert_dir/fullchain.pem"
    cp -f "$src_key" "$cert_dir/privkey.pem"
    echo "✓ Copied certificate from acme.sh store for $domain"
  else
    generate_self_signed_cert "$domain" "$cert_dir"
  fi
}

generate_self_signed_cert() {
  local domain="$1"
  local cert_dir="$2"
  
  echo "Generating self-signed certificate for $domain..."
  require_cmd openssl || abort "openssl is required to generate a temporary certificate"
  
  openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
    -keyout "$cert_dir/privkey.pem" \
    -out "$cert_dir/fullchain.pem" \
    -subj "/CN=$domain" >/dev/null 2>&1
  
  echo "✓ Self-signed certificate generated for $domain"
}

# Install acme.sh
install_acme_sh

# Create certificate directories
ensure_dir "$NGINX_DIR/ssl/panel"
ensure_dir "$NGINX_DIR/ssl/subscription"

# Stop nginx container if running to free port 80 for certificate issuance
echo "Stopping nginx container to free port 80 for certificate issuance..."
(cd "$NGINX_DIR" && docker compose down >/dev/null 2>&1 || true)

# Issue certificates for both domains
set +e
issue_certificate "$PANEL_DOMAIN" "$NGINX_DIR/ssl/panel"
issue_certificate "$SUB_DOMAIN" "$NGINX_DIR/ssl/subscription"
set -e

print_header "SSL certificates processed, starting Nginx"

# Function to manage containers
manage_containers() {
  local action="$1"
  local service="$2"
  
  case "$action" in
    "stop")
      echo "Stopping $service container..."
      (cd "$NGINX_DIR" && docker compose down >/dev/null 2>&1 || true)
      ;;
    "start")
      echo "Starting $service container..."
      (cd "$NGINX_DIR" && docker compose up -d --force-recreate)
      ;;
    "restart")
      echo "Restarting $service container..."
      (cd "$NGINX_DIR" && docker compose down >/dev/null 2>&1 || true)
      sleep 2
      (cd "$NGINX_DIR" && docker compose up -d --force-recreate)
      ;;
  esac
}

print_header "Writing optimized Nginx configuration"
write_nginx_config() {
  cat > "$NGINX_DIR/nginx.conf" <<EOF
# Remnawave Nginx Configuration
# Optimized for security and performance

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=login:10m rate=5r/m;
    
    # Basic settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;
    
    # MIME types
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Logging
    log_format main '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';
    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log warn;

    # Upstream definitions
    upstream remnawave_backend {
        server remnawave:3000 max_fails=3 fail_timeout=30s;
        keepalive 32;
    }

    upstream remnawave_subscription {
        server remnawave-subscription:3010 max_fails=3 fail_timeout=30s;
        keepalive 32;
    }

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name $PANEL_DOMAIN $SUB_DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

# Panel server block
server {
    server_name $PANEL_DOMAIN;
    
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/panel/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/panel/privkey.pem;
    ssl_trusted_certificate /etc/nginx/ssl/panel/fullchain.pem;
    
    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    
    # SSL session optimization
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    
    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Rate limiting for API endpoints
    location /api/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://remnawave_backend;
        include /etc/nginx/conf.d/proxy_params.conf;
    }
    
    # Rate limiting for login
    location /auth/login {
        limit_req zone=login burst=5 nodelay;
        proxy_pass http://remnawave_backend;
        include /etc/nginx/conf.d/proxy_params.conf;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Main application
    location / {
        proxy_pass http://remnawave_backend;
        include /etc/nginx/conf.d/proxy_params.conf;
    }
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 1000;
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

# Subscription server block
server {
    server_name $SUB_DOMAIN;
    
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    
    # SSL Configuration
    ssl_certificate /etc/nginx/ssl/subscription/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/subscription/privkey.pem;
    ssl_trusted_certificate /etc/nginx/ssl/subscription/fullchain.pem;
    
    # Modern SSL configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers off;
    
    # SSL session optimization
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;
    
    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 1.1.1.1 1.0.0.1 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=63072000" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Main application
    location / {
        proxy_pass http://remnawave_subscription;
        include /etc/nginx/conf.d/proxy_params.conf;
    }
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_min_length 1000;
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

    # Default server block (reject all other requests)
    server {
        listen 443 ssl default_server;
        listen [::]:443 ssl default_server;
        server_name _;
        ssl_reject_handshake on;
    }
}
EOF
}

write_proxy_params() {
  cat > "$NGINX_DIR/proxy_params.conf" <<'EOF'
# Proxy parameters for Remnawave
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection 'upgrade';
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Host $host;
proxy_set_header X-Forwarded-Port $server_port;
proxy_cache_bypass $http_upgrade;
proxy_redirect off;
proxy_buffering off;
proxy_read_timeout 86400;
proxy_send_timeout 86400;
EOF
}

# Write configurations
write_nginx_config
write_proxy_params

print_header "Writing optimized Nginx docker-compose.yml"
write_nginx_compose() {
  cat > "$NGINX_DIR/docker-compose.yml" <<EOF
services:
  remnawave-nginx:
    image: nginx:1.28-alpine
    container_name: remnawave-nginx
    hostname: remnawave-nginx
    restart: unless-stopped
    ports:
      - '80:80'
      - '443:443'
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./proxy_params.conf:/etc/nginx/conf.d/proxy_params.conf:ro
      - ./ssl:/etc/nginx/ssl:ro
    environment:
      - TZ=UTC
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    networks:
      - remnawave-network
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge
    external: true
EOF
}

write_nginx_compose

print_header "Writing optimized Subscription Page docker-compose.yml"
write_subscription_compose() {
  cat > "$SUB_DIR/docker-compose.yml" <<EOF
services:
  remnawave-subscription:
    image: remnawave/subscription-page:latest
    container_name: remnawave-subscription
    restart: unless-stopped
    environment:
      - REMNAWAVE_PANEL_URL=https://$PANEL_DOMAIN
      - APP_PORT=3010
      - META_TITLE="Subscription page"
      - META_DESCRIPTION="Subscription page for $PANEL_DOMAIN"
      - TZ=UTC
    ports:
      - '127.0.0.1:3010:3010'
    volumes:
      - './app-config.json:/opt/app/frontend/assets/app-config.json:ro'
    networks:
      - remnawave-network
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost:3010/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

networks:
  remnawave-network:
    name: remnawave-network
    driver: bridge
    external: true
EOF
}

write_subscription_compose

print_header "Starting services"
start_services() {
  echo "Starting Subscription Page..."
  (cd "$SUB_DIR" && docker compose up -d --force-recreate)
  
  echo "Waiting for subscription service to be ready..."
  sleep 10
  
  echo "Starting Nginx..."
  (cd "$NGINX_DIR" && docker compose up -d --force-recreate)
  
  echo "Waiting for Nginx to be ready..."
  sleep 5
  
  # Verify nginx is running properly
  if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "remnawave-nginx.*Up"; then
    echo "✓ All services started successfully"
  else
    echo "⚠ Nginx container may have issues. Check logs with: docker logs remnawave-nginx"
  fi
}

start_services

# Function to check service status
check_service_status() {
  echo ""
  echo "============================================================"
  echo "Service Status Check"
  echo "============================================================"
  
  # Check nginx
  if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "remnawave-nginx.*Up"; then
    echo "✓ Nginx: Running"
  else
    echo "✗ Nginx: Not running or has issues"
    echo "  Check logs: docker logs remnawave-nginx"
  fi
  
  # Check subscription
  if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "remnawave-subscription.*Up"; then
    echo "✓ Subscription: Running"
  else
    echo "✗ Subscription: Not running or has issues"
    echo "  Check logs: docker logs remnawave-subscription"
  fi
  
  # Check backend
  if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "remnawave.*Up"; then
    echo "✓ Backend: Running"
  else
    echo "✗ Backend: Not running or has issues"
    echo "  Check logs: docker logs remnawave"
  fi
  
  echo ""
  echo "Container Status:"
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep remnawave
}

check_service_status

echo ""
echo "All set! Installation completed successfully."
echo "Panel:        https://$PANEL_DOMAIN/"
echo "Subscription: https://$SUB_DOMAIN/"
echo ""
echo "Note: Ensure DNS for $PANEL_DOMAIN and $SUB_DOMAIN point to this server and port 8443 was free during certificate issuance."