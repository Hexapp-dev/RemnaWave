#!/bin/bash

set -e

echo "=== RemnaWave Panel Installer ==="

# --- User Inputs ---
read -p "Enter FRONT_END_DOMAIN (e.g. panel.example.com): " FRONT_END_DOMAIN
read -p "Enter SUB_PUBLIC_DOMAIN (default: ${FRONT_END_DOMAIN}/api/sub): " SUB_PUBLIC_DOMAIN
SUB_PUBLIC_DOMAIN=${SUB_PUBLIC_DOMAIN:-${FRONT_END_DOMAIN}/api/sub}

echo -e "\nYou entered:"
echo "  FRONT_END_DOMAIN = $FRONT_END_DOMAIN"
echo "  SUB_PUBLIC_DOMAIN = $SUB_PUBLIC_DOMAIN"

read -p "Proceed with installation? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Installation aborted."
    exit 1
fi

# --- Check Ports ---
echo ">>> Checking ports 80 and 443..."
for PORT in 80 443; do
    if ss -tulpn | grep -q ":$PORT "; then
        echo "Port $PORT is already in use. Please free it before running the installer."
        exit 1
    fi
done

# --- Install Dependencies ---
echo ">>> Installing dependencies..."
apt update
apt install -y lsb-release ca-certificates curl software-properties-common gnupg2 ufw

# --- Docker & Docker Compose ---
echo ">>> Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | bash
fi

echo ">>> Installing Docker Compose..."
DOCKER_COMPOSE_VERSION="2.24.1"
if ! docker compose version &> /dev/null; then
    curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# --- Setup Directories ---
echo ">>> Setting up RemnaWave directories..."
mkdir -p /opt/remnawave
cd /opt/remnawave

# --- Download docker-compose.yml and .env.sample ---
echo ">>> Downloading docker-compose.yml and .env.sample..."
curl -sSL https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml -o docker-compose.yml
curl -sSL https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample -o .env.sample

# --- Generate Secrets ---
echo ">>> Generating secrets..."
DB_PASSWORD=$(openssl rand -hex 16)
METRICS_PASSWORD=$(openssl rand -hex 16)
WEBHOOK_SECRET=$(openssl rand -hex 16)

# --- Configure .env ---
echo ">>> Configuring .env..."
cp .env.sample .env
sed -i "s|FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=$FRONT_END_DOMAIN|" .env
sed -i "s|SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$SUB_PUBLIC_DOMAIN|" .env
sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$DB_PASSWORD|" .env
sed -i "s|METRICS_PASSWORD=.*|METRICS_PASSWORD=$METRICS_PASSWORD|" .env
sed -i "s|WEBHOOK_SECRET=.*|WEBHOOK_SECRET=$WEBHOOK_SECRET|" .env

# --- Start Docker ---
echo ">>> Starting RemnaWave with Docker..."
docker compose pull
docker compose up -d

# --- Install Nginx ---
echo ">>> Installing Nginx..."
apt install -y nginx
cat > /etc/nginx/sites-available/remnawave <<EOL
server {
    listen 80;
    server_name $FRONT_END_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

ln -sf /etc/nginx/sites-available/remnawave /etc/nginx/sites-enabled/remnawave
nginx -t && systemctl restart nginx

# --- Obtain SSL ---
echo ">>> Attempting to obtain SSL certificate..."
if ! apt install -y certbot python3-certbot-nginx; then
    echo "Certbot installation failed. Continuing with HTTP..."
else
    if ! certbot --nginx -d "$FRONT_END_DOMAIN" --non-interactive --agree-tos -m admin@$FRONT_END_DOMAIN; then
        echo "⚠️ SSL setup failed, continuing with HTTP. You can fix SSL manually later."
    fi
fi

# --- Completion ---
echo -e "\n=== Installation complete! ==="
echo "Panel should be available at: http://$FRONT_END_DOMAIN (or https if SSL succeeded)"
echo ""
echo "Database password: $DB_PASSWORD"
echo "Metrics password: $METRICS_PASSWORD"
echo "Webhook secret header: $WEBHOOK_SECRET"
echo ""
echo "(These values are saved in /opt/remnawave/.env)"
echo "⚠️ If a new kernel was installed, please reboot the server to apply changes."
