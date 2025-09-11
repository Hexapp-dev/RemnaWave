#!/bin/bash
set -euo pipefail

echo "=== RemNaWave Panel Auto Installer ==="

# Preconditions: must be root, Debian/Ubuntu family
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "This installer must be run as root." >&2
    exit 1
fi
if [ -r /etc/os-release ]; then
    . /etc/os-release
    case "${ID_LIKE:-$ID}" in
        *debian*) : ;;
        *) echo "Supported only on Debian/Ubuntu family." >&2; exit 1 ;;
    esac
fi

# Input (env-first; fallback to prompts if TTY)
NON_INTERACTIVE="${NON_INTERACTIVE:-}"
FRONT_END_DOMAIN="${FRONT_END_DOMAIN:-}"
SUB_PUBLIC_DOMAIN="${SUB_PUBLIC_DOMAIN:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"

if [ -z "${FRONT_END_DOMAIN}" ]; then
    if [ -t 0 ]; then
        read -p "Enter FRONT_END_DOMAIN (e.g. panel.example.com): " FRONT_END_DOMAIN
    else
        echo "FRONT_END_DOMAIN is required." >&2; exit 1
    fi
fi
SUB_PUBLIC_DOMAIN_DEFAULT="$FRONT_END_DOMAIN/api/sub"
if [ -z "${SUB_PUBLIC_DOMAIN}" ]; then
    if [ -t 0 ]; then
        read -p "Enter SUB_PUBLIC_DOMAIN (default: $SUB_PUBLIC_DOMAIN_DEFAULT): " SUB_PUBLIC_DOMAIN
        SUB_PUBLIC_DOMAIN=${SUB_PUBLIC_DOMAIN:-$SUB_PUBLIC_DOMAIN_DEFAULT}
    else
        SUB_PUBLIC_DOMAIN=$SUB_PUBLIC_DOMAIN_DEFAULT
    fi
fi
if [ -z "${ADMIN_EMAIL}" ]; then
    if [ -t 0 ]; then
        read -p "Enter admin email for Certbot (e.g. admin@$FRONT_END_DOMAIN): " ADMIN_EMAIL
    else
        ADMIN_EMAIL="admin@$FRONT_END_DOMAIN"
    fi
fi

echo -e "\nYou entered:\n  FRONT_END_DOMAIN = $FRONT_END_DOMAIN\n  SUB_PUBLIC_DOMAIN = $SUB_PUBLIC_DOMAIN\n  ADMIN_EMAIL = $ADMIN_EMAIL"
echo "Proceeding with installation..."
sleep 1

# Dependencies
echo ">>> Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y lsb-release ca-certificates curl software-properties-common gnupg2 git unzip socat \
    openssl lsof psmisc nginx certbot python3-certbot-nginx

# Docker
if ! command -v docker >/dev/null 2>&1; then
    echo ">>> Installing Docker..."
    curl -fsSL https://get.docker.com | sh
fi

# Compose (prefer v2 plugin)
COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    echo ">>> Installing docker compose plugin..."
    apt-get install -y docker-compose-plugin || true
    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        COMPOSE_CMD="docker-compose"
    else
        echo "Failed to install Docker Compose." >&2; exit 1
    fi
fi

# Workspace
INSTALL_DIR="/opt/remnawave"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

echo ">>> Downloading docker-compose.yml and .env.example..."
curl -s -L https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml -o docker-compose.yml
curl -s -L https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample -o .env.example

echo ">>> Configuring .env..."
umask 027
if [ -f .env ]; then
    echo "Found existing .env. Reusing existing secrets."
else
    cp .env.example .env
    POSTGRES_PASSWORD=$(openssl rand -hex 16)
    METRICS_PASSWORD=$(openssl rand -hex 16)
    WEBHOOK_SECRET=$(openssl rand -hex 16)
    grep -q '^FRONT_END_DOMAIN=' .env && sed -i "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=$FRONT_END_DOMAIN|" .env || echo "FRONT_END_DOMAIN=$FRONT_END_DOMAIN" >> .env
    grep -q '^SUB_PUBLIC_DOMAIN=' .env && sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$SUB_PUBLIC_DOMAIN|" .env || echo "SUB_PUBLIC_DOMAIN=$SUB_PUBLIC_DOMAIN" >> .env
    grep -q '^POSTGRES_PASSWORD=' .env && sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" .env || echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> .env
    grep -q '^METRICS_PASSWORD=' .env && sed -i "s|^METRICS_PASSWORD=.*|METRICS_PASSWORD=$METRICS_PASSWORD|" .env || echo "METRICS_PASSWORD=$METRICS_PASSWORD" >> .env
    grep -q '^WEBHOOK_SECRET=' .env && sed -i "s|^WEBHOOK_SECRET=.*|WEBHOOK_SECRET=$WEBHOOK_SECRET|" .env || echo "WEBHOOK_SECRET=$WEBHOOK_SECRET" >> .env
    grep -q '^POSTGRES_USER=' .env || echo "POSTGRES_USER=postgres" >> .env
    grep -q '^POSTGRES_DB=' .env || echo "POSTGRES_DB=postgres" >> .env
fi

set +u
. ./.env
set -u
DB_USER="${POSTGRES_USER:-postgres}"
DB_PASS="${POSTGRES_PASSWORD}"
DB_NAME="${POSTGRES_DB:-postgres}"
grep -q '^DATABASE_URL=' .env && sed -i "/^DATABASE_URL=/d" .env || true
echo "DATABASE_URL=postgresql://${DB_USER}:${DB_PASS}@remnawave-db:5432/${DB_NAME}?schema=public" >> .env
chmod 640 .env

echo ">>> Stopping any existing RemnaWave stack..."
$COMPOSE_CMD -p remnawave down --remove-orphans || true
echo ">>> Starting RemnaWave with Docker..."
$COMPOSE_CMD -p remnawave up -d --remove-orphans

echo ">>> Configuring Nginx..."
NGINX_CONF="/etc/nginx/sites-available/remnawave.conf"
cat > "$NGINX_CONF" <<EOL
server {
    listen 80;
    listen [::]:80;
    server_name $FRONT_END_DOMAIN;

    client_max_body_size 16m;

    location / {
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
        proxy_pass http://127.0.0.1:3000;
    }

    location /api/sub {
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 60s;
        proxy_pass http://127.0.0.1:8000;
    }
}
EOL

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/remnawave.conf
nginx -t
systemctl restart nginx

echo ">>> Obtaining SSL certificate with Certbot..."
certbot --nginx -d "$FRONT_END_DOMAIN" --non-interactive --agree-tos -m "$ADMIN_EMAIL" || true

echo -e "\n=== Installation complete! ==="
echo "Panel should be available at: https://$FRONT_END_DOMAIN"
echo "Database password: ${POSTGRES_PASSWORD:-$(grep '^POSTGRES_PASSWORD=' .env | cut -d'=' -f2)}"
echo "Metrics password: ${METRICS_PASSWORD:-$(grep '^METRICS_PASSWORD=' .env | cut -d'=' -f2)}"
echo "Webhook secret header: ${WEBHOOK_SECRET:-$(grep '^WEBHOOK_SECRET=' .env | cut -d'=' -f2)}"
echo "(These values are saved in $INSTALL_DIR/.env)"


