#!/usr/bin/env bash
#
# Автоматическая настройка Nginx + SSL для Hyperswitch
# Домен: dagstatus.ru
#

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DOMAIN="dagstatus.ru"
EMAIL="admin@${DOMAIN}"

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗ ОШИБКА:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

# Проверка sudo
if [[ $EUID -eq 0 ]]; then
    log_error "Не запускайте этот скрипт от root! Используйте обычного пользователя с sudo."
    exit 1
fi

echo -e "${GREEN}${BOLD}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║         Настройка Nginx + SSL для Hyperswitch                       ║
║         Домен: dagstatus.ru                                          ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

# Проверка DNS
log "Проверка DNS для ${DOMAIN}..."
SERVER_IP=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)
DOMAIN_IP=$(dig +short ${DOMAIN} | tail -n1)

if [[ -z "$DOMAIN_IP" ]]; then
    log_error "Домен ${DOMAIN} не резолвится!"
    log_warning "Настройте A-запись у регистратора домена, чтобы она указывала на ${SERVER_IP}"
    exit 1
fi

if [[ "$DOMAIN_IP" != "$SERVER_IP" ]]; then
    log_warning "Домен указывает на ${DOMAIN_IP}, а IP сервера ${SERVER_IP}"
    read -p "Продолжить? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    log_success "DNS настроен корректно: ${DOMAIN} → ${SERVER_IP}"
fi

# Установка Nginx
log "Установка Nginx..."
sudo apt update -qq
sudo apt install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx
log_success "Nginx установлен"

# Создание конфигурации Nginx
log "Создание конфигурации для ${DOMAIN}..."
sudo tee /etc/nginx/sites-available/${DOMAIN} > /dev/null << 'NGINX_EOF'
# Hyperswitch Nginx Configuration for dagstatus.ru

# Ограничение размера загружаемых файлов
client_max_body_size 16M;

# Upstream для API Server
upstream hyperswitch_api {
    server 127.0.0.1:8080;
    keepalive 32;
}

# Upstream для Control Center
upstream hyperswitch_dashboard {
    server 127.0.0.1:9000;
    keepalive 32;
}

# Upstream для Web SDK
upstream hyperswitch_sdk {
    server 127.0.0.1:9050;
    keepalive 32;
}

# Upstream для Grafana
upstream grafana {
    server 127.0.0.1:3000;
    keepalive 16;
}

# HTTP сервер (будет автоматически перенаправлять на HTTPS после установки SSL)
server {
    listen 80;
    listen [::]:80;
    server_name dagstatus.ru www.dagstatus.ru;

    # Логи
    access_log /var/log/nginx/hyperswitch-access.log;
    error_log /var/log/nginx/hyperswitch-error.log;

    # Временная заглушка для certbot
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # API Server
    location /api {
        proxy_pass http://hyperswitch_api;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;

        # Таймауты
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Control Center (корень)
    location / {
        proxy_pass http://hyperswitch_dashboard;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Web SDK
    location /sdk {
        proxy_pass http://hyperswitch_sdk;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
    }

    # Grafana
    location /grafana/ {
        rewrite ^/grafana/(.*) /$1 break;
        proxy_pass http://grafana;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Health check endpoint
    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
NGINX_EOF

# Активация конфигурации
sudo ln -sf /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Проверка конфигурации
log "Проверка конфигурации Nginx..."
sudo nginx -t

# Перезапуск Nginx
sudo systemctl reload nginx
log_success "Nginx настроен"

# Установка Certbot
log "Установка Certbot для Let's Encrypt..."
sudo apt install -y certbot python3-certbot-nginx
log_success "Certbot установлен"

# Получение SSL сертификата
log "Получение SSL сертификата для ${DOMAIN}..."
log_warning "Certbot попросит ввести email и согласиться с условиями"
echo

sudo certbot --nginx -d ${DOMAIN} -d www.${DOMAIN} \
    --non-interactive \
    --agree-tos \
    --email ${EMAIL} \
    --redirect

log_success "SSL сертификат установлен"

# Автоматическое обновление сертификата
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
log_success "Автоматическое обновление сертификата настроено"

# Настройка Firewall
log "Настройка UFW Firewall..."
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp comment 'SSH'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw reload
log_success "Firewall настроен"

# Итоговая информация
echo
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                                      ║${NC}"
echo -e "${GREEN}║              НАСТРОЙКА ЗАВЕРШЕНА УСПЕШНО!                           ║${NC}"
echo -e "${GREEN}║                                                                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo
log_success "Hyperswitch доступен по адресу: https://${DOMAIN}"
echo
echo -e "${BLUE}📍 ДОСТУП К СЕРВИСАМ:${NC}"
echo
echo -e "  ${GREEN}Control Center:${NC}  https://${DOMAIN}/"
echo -e "  ${GREEN}API Server:${NC}      https://${DOMAIN}/api/"
echo -e "  ${GREEN}Web SDK:${NC}         https://${DOMAIN}/sdk/"
echo -e "  ${GREEN}Grafana:${NC}         https://${DOMAIN}/grafana/"
echo
echo -e "${BLUE}🔑 УЧЕТНЫЕ ДАННЫЕ:${NC}"
echo -e "  Email:    demo@hyperswitch.com"
echo -e "  Password: Hyperswitch@123"
echo
echo -e "${BLUE}🔒 SSL:${NC}"
echo -e "  Сертификат Let's Encrypt установлен"
echo -e "  Автоматическое обновление: включено"
echo
echo -e "${BLUE}🔥 FIREWALL:${NC}"
echo -e "  UFW активен"
sudo ufw status numbered
echo
log_success "Готово! Откройте https://${DOMAIN} в браузере"
echo
