#!/bin/bash
set -e

echo "=== Remnawave Panel Installer ==="

# ---- 1. گرفتن ورودی از کاربر ----
read -p "Enter FRONT_END_DOMAIN (e.g. panel.example.com): " FRONT_END_DOMAIN
DEFAULT_SUB_PUBLIC_DOMAIN="$FRONT_END_DOMAIN/api/sub"
read -p "Enter SUB_PUBLIC_DOMAIN (default: $DEFAULT_SUB_PUBLIC_DOMAIN): " SUB_PUBLIC_DOMAIN
SUB_PUBLIC_DOMAIN=${SUB_PUBLIC_DOMAIN:-$DEFAULT_SUB_PUBLIC_DOMAIN}

echo ""
echo "You entered:"
echo "  FRONT_END_DOMAIN = $FRONT_END_DOMAIN"
echo "  SUB_PUBLIC_DOMAIN = $SUB_PUBLIC_DOMAIN"
read -p "Proceed with installation? (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
  echo "Installation aborted."
  exit 1
fi

# ---- 2. جلوگیری از توقف needrestart ----
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l  # حالت "none of the above"

# ---- 3. نصب پیش‌نیازها ----
echo ">>> Installing dependencies..."
apt update -y
apt install -y curl gnupg2 ca-certificates lsb-release software-properties-common

if ! command -v docker >/dev/null 2>&1; then
  echo ">>> Installing Docker..."
  curl -fsSL https://get.docker.com | sh
fi

if ! command -v docker compose >/dev/null 2>&1; then
  echo ">>> Installing docker-compose plugin..."
  apt install -y docker-compose-plugin
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo ">>> Installing Nginx..."
  apt install -y nginx
fi

if ! command -v certbot >/dev/null 2>&1; then
  echo ">>> Installing Certbot..."
  apt install -y certbot python3-certbot-nginx
fi

# ---- 4. آماده‌سازی فایل‌ها ----
INSTALL_DIR="/opt/remnawave"
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

echo ">>> Downloading docker-compose-prod.yml and .env.sample..."
curl -fSL https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/docker-compose-prod.yml -o docker-compose.yml
curl -fSL https://raw.githubusercontent.com/remnawave/backend/refs/heads/main/.env.sample -o .env

# ---- 5. تولید secrets ----
echo ">>> Generating secrets..."
POSTGRES_PASSWORD=$(openssl rand -hex 16)
JWT_AUTH_SECRET=$(openssl rand -hex 32)
JWT_API_TOKENS_SECRET=$(openssl rand -hex 32)
METRICS_PASS=$(openssl rand -hex 16)
WEBHOOK_SECRET_HEADER=$(openssl rand -hex 16)

# ---- 6. ساخت فایل .env ----
echo ">>> Configuring .env..."
sed -i "s|^FRONT_END_DOMAIN=.*|FRONT_END_DOMAIN=$FRONT_END_DOMAIN|" .env
sed -i "s|^SUB_PUBLIC_DOMAIN=.*|SUB_PUBLIC_DOMAIN=$SUB_PUBLIC_DOMAIN|" .env
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|" .env
sed -i "s|^JWT_AUTH_SECRET=.*|JWT_AUTH_SECRET=$JWT_AUTH_SECRET|" .env
sed -i "s|^JWT_API_TOKENS_SECRET=.*|JWT_API_TOKENS_SECRET=$JWT_API_TOKENS_SECRET|" .env
sed -i "s|^METRICS_PASS=.*|METRICS_PASS=$METRICS_PASS|" .env
sed -i "s|^WEBHOOK_SECRET_HEADER=.*|WEBHOOK_SECRET_HEADER=$WEBHOOK_SECRET_HEADER|" .env

# ---- 7. ران کردن Remnawave ----
echo ">>> Starting Remnawave with Docker..."
docker compose up -d

# ---- 8. کانفیگ Nginx ----
NGINX_CONF="/etc/nginx/sites-available/remnawave.conf"
echo ">>> Configuring Nginx..."
cat > $NGINX_CONF <<EOF
server {
    listen 80;
    server_name $FRONT_END_DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

ln -sf $NGINX_CONF /etc/nginx/sites-enabled/remnawave.conf
nginx -t
systemctl reload nginx

# ---- 9. فعال‌سازی SSL ----
echo ">>> Obtaining SSL certificate..."
certbot --nginx -d $FRONT_END_DOMAIN --non-interactive --agree-tos -m admin@$FRONT_END_DOMAIN --redirect || echo "⚠️ SSL setup failed, please check DNS and try certbot manually."

# ---- 10. پایان ----
echo ""
echo "=== Installation complete! ==="
echo "Panel should be available at: https://$FRONT_END_DOMAIN"
echo ""
echo "Database password: $POSTGRES_PASSWORD"
echo "Metrics password: $METRICS_PASS"
echo "Webhook secret header: $WEBHOOK_SECRET_HEADER"
echo ""
echo "(These values are saved in $INSTALL_DIR/.env)"
echo ""
echo "⚠️ If a new kernel was installed, please reboot the server to apply changes."
