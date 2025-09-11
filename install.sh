#!/bin/bash
set -e

# === RemnaWave Full Auto Installer ===

echo "=== RemNaWave Panel Auto Installer ==="

# --- User Input ---
read -p "Enter FRONT_END_DOMAIN (e.g. panel.example.com): " FRONT_END_DOMAIN
SUB_PUBLIC_DOMAIN_DEFAULT="$FRONT_END_DOMAIN/api/sub"
read -p "Enter SUB_PUBLIC_DOMAIN (default: $SUB_PUBLIC_DOMAIN_DEFAULT): " SUB_PUBLIC_DOMAIN
SUB_PUBLIC_DOMAIN=${SUB_PUBLIC_DOMAIN:-$SUB_PUBLIC_DOMAIN_DEFAULT}

echo -e "\nYou entered:\n  FRONT_END_DOMAIN = $FRONT_END_DOMAIN\n  SUB_PUBLIC_DOMAIN = $SUB_PUBLIC_DOMAIN"
echo "Proceed with installation automatically..."
sleep 2

# --- Stop and remove old containers ---
echo ">>> Stopping and removing old RemnaWave containers..."
if [ "$(docker ps -aq --filter "name=remnawave")" ]; then
    docker stop $(docker ps -aq --filter "name=remnawave") || true
    docker rm -f $(docker ps -aq --filter "name=remnawave") || true
    echo "Old containers removed."
fi

# --- Free ports 80 & 443 ---
echo ">>> Checking ports 80 and 443..."
for PORT in 80 443; do
    if lsof -i:$PORT >/dev/null; then
        echo "Port $PORT is in use. Killing process..."
        fuser -k $PORT/tcp || true
    fi
done

# --- Update & install dependencies ---
echo ">>> Installing dependencies..."
apt update -y
apt install -y lsb-release ca-certificates curl software-properties-common gnupg2 git unzip socat

# --- Install Docker if not exists ---
if ! command -v docker >/dev/null; then
    echo ">>> Installing Docker..."
    curl -fsSL https://get.docker.com | sh
fi

# --- Install Docker Compose if not exists ---
if ! command -v docker-compose >/dev/null; then
    echo ">>> Installing Docker Compose..."
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep -Po '"tag_name": "\K.*?(?=")')
    curl -L "https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
fi

# --- Setup RemnaWave folder ---
INSTALL_DIR="/opt/remnawave"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# --- Download docker-compose.yml and .env.example ---
echo ">>> Downloading docker-compose.yml and .env.example..."
curl -s -L https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml -o docker-compose.yml
curl -s -L https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample -o .env.example

# --- Generate secrets ---
echo ">>> Generating secrets..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
METRICS_PASSWORD=$(openssl rand -hex 16)
WEBHOOK_SECRET=$(openssl rand -hex 16)

# --- Configure .env ---
echo ">>> Configuring .env..."
cp .env.example .env
sed -i "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=$FRONT_END_DOMAIN|" .env
sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$SUB_PUBLIC_DOMAIN|" .env
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" .env
sed -i "s|^METRICS_PASSWORD=.*|METRICS_PASSWORD=$METRICS_PASSWORD|" .env
sed -i "s|^WEBHOOK_SECRET=.*|WEBHOOK_SECRET=$WEBHOOK_SECRET|" .env

# --- Start Docker containers ---
echo ">>> Starting RemnaWave with Docker..."
docker-compose up -d --remove-orphans

# --- Install Nginx & Certbot ---
echo ">>> Installing Nginx & Certbot..."
apt install -y nginx certbot python3-certbot-nginx

# --- Configure Nginx ---
echo ">>> Configuring Nginx..."
NGINX_CONF="/etc/nginx/sites-available/remnawave.conf"
cat > $NGINX_CONF <<EOL
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

    location /api/sub {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOL

ln -sf $NGINX_CONF /etc/nginx/sites-enabled/remnawave.conf
nginx -t
systemctl restart nginx

# --- Obtain SSL Certificate ---
echo ">>> Obtaining SSL certificate with Certbot..."
certbot --nginx -d $FRONT_END_DOMAIN --non-interactive --agree-tos -m admin@$FRONT_END_DOMAIN || true

# --- Done ---
echo -e "\n=== Installation complete! ==="
echo "Panel should be available at: https://$FRONT_END_DOMAIN"
echo "Database password: $POSTGRES_PASSWORD"
echo "Metrics password: $METRICS_PASSWORD"
echo "Webhook secret header: $WEBHOOK_SECRET"
echo "(These values are saved in $INSTALL_DIR/.env)"
