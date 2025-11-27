#!/usr/bin/env bash
#
# Установка и настройка YooKassa Proxy для Hyperswitch
#

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

echo -e "${GREEN}${BOLD}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║       Установка YooKassa Proxy для Hyperswitch                     ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

INSTALL_DIR="/opt/yookassa-proxy"

# Проверка прав
if [[ $EUID -eq 0 ]]; then
    log_error "Не запускайте этот скрипт от root!"
    exit 1
fi

# Запрос учётных данных YooKassa
echo
log_warning "Получите учётные данные в личном кабинете YooKassa:"
log_warning "https://yookassa.ru/my/merchant/integration/api-keys"
echo

read -p "Введите Shop ID: " YOOKASSA_SHOP_ID
read -sp "Введите Secret Key: " YOOKASSA_SECRET_KEY
echo
echo

if [[ -z "$YOOKASSA_SHOP_ID" ]] || [[ -z "$YOOKASSA_SECRET_KEY" ]]; then
    log_error "Shop ID и Secret Key обязательны!"
    exit 1
fi

# Создание директории установки
log "Создание директории ${INSTALL_DIR}..."
sudo mkdir -p "$INSTALL_DIR"
sudo chown "$USER":"$USER" "$INSTALL_DIR"
log_success "Директория создана"

# Копирование файлов
log "Копирование файлов прокси-сервиса..."
cp package.json "$INSTALL_DIR/"
cp server.js "$INSTALL_DIR/"
cp Dockerfile "$INSTALL_DIR/"
cp docker-compose.yml "$INSTALL_DIR/"
log_success "Файлы скопированы"

# Создание .env файла
log "Создание конфигурации..."
cat > "$INSTALL_DIR/.env" << EOF
# YooKassa Configuration
YOOKASSA_SHOP_ID=${YOOKASSA_SHOP_ID}
YOOKASSA_SECRET_KEY=${YOOKASSA_SECRET_KEY}

# Server Configuration
PORT=8888
NODE_ENV=production

# Hyperswitch Integration
DEFAULT_RETURN_URL=https://dagstatus.ru/payment/success
HYPERSWITCH_WEBHOOK_URL=https://dagstatus.ru/api/webhooks/yookassa
EOF

chmod 600 "$INSTALL_DIR/.env"
log_success "Конфигурация создана"

# Сборка и запуск Docker контейнера
log "Сборка Docker образа..."
cd "$INSTALL_DIR"
docker build -t yookassa-proxy:latest .
log_success "Образ собран"

log "Запуск контейнера..."
docker compose up -d
log_success "Контейнер запущен"

# Ожидание готовности
log "Ожидание готовности сервиса..."
sleep 5

# Проверка здоровья
if curl -f http://localhost:8888/health > /dev/null 2>&1; then
    log_success "YooKassa Proxy работает"
else
    log_error "Не удалось запустить YooKassa Proxy"
    log "Проверьте логи: docker logs yookassa-proxy"
    exit 1
fi

# Настройка Nginx
log "Настройка Nginx reverse proxy..."
sudo tee /etc/nginx/sites-available/yookassa-proxy > /dev/null << 'NGINX_EOF'
# YooKassa Proxy
location /yookassa/ {
    rewrite ^/yookassa/(.*) /$1 break;
    proxy_pass http://127.0.0.1:8888;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_cache_bypass $http_upgrade;

    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
}
NGINX_EOF

# Добавить location в основную конфигурацию dagstatus.ru
if ! grep -q "include /etc/nginx/sites-available/yookassa-proxy" /etc/nginx/sites-available/dagstatus.ru; then
    log "Добавление location в Nginx конфигурацию..."

    # Найти HTTPS server block и добавить include перед последней }
    sudo sed -i '/listen 443 ssl/,/^}$/ {
        /^}$/i\    # YooKassa Proxy\n    include /etc/nginx/sites-available/yookassa-proxy;
    }' /etc/nginx/sites-available/dagstatus.ru

    log_success "Location добавлен"
fi

# Проверка и перезагрузка Nginx
sudo nginx -t && sudo systemctl reload nginx
log_success "Nginx настроен"

# Настройка Custom Billing коннектора в Hyperswitch
log "Настройка Custom Billing коннектора..."

ADMIN_API_KEY=$(cat /opt/hyperswitch/.credentials 2>/dev/null | grep ADMIN_API_KEY | cut -d'=' -f2 || echo "")

if [[ -z "$ADMIN_API_KEY" ]]; then
    log_warning "Не удалось получить ADMIN_API_KEY автоматически"
    log "Настройте коннектор вручную через API или Control Center"
else
    # Создать Custom Billing коннектор
    CONNECTOR_RESPONSE=$(curl -s -X POST "https://dagstatus.ru/api/account/merchant_default/connectors" \
      -H "Content-Type: application/json" \
      -H "api-key: ${ADMIN_API_KEY}" \
      -d "{
        \"connector_type\": \"fiz_operations\",
        \"connector_name\": \"custombilling\",
        \"connector_account_details\": {
          \"auth_type\": \"HeaderKey\",
          \"api_key\": \"yookassa_proxy_key\",
          \"api_secret\": \"${YOOKASSA_SECRET_KEY}\",
          \"base_url\": \"https://dagstatus.ru/yookassa\"
        },
        \"test_mode\": false,
        \"disabled\": false,
        \"payment_methods_enabled\": [
          {
            \"payment_method\": \"card\",
            \"payment_method_types\": [\"credit\", \"debit\"]
          }
        ],
        \"metadata\": {
          \"description\": \"YooKassa via Custom Proxy\",
          \"provider\": \"yookassa\"
        }
      }")

    if echo "$CONNECTOR_RESPONSE" | jq -e '.merchant_connector_id' > /dev/null 2>&1; then
        log_success "Custom Billing коннектор настроен"
    else
        log_warning "Ошибка настройки коннектора, настройте вручную"
    fi
fi

# Итоговая информация
echo
echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              YooKassa Proxy установлен успешно!                     ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo
log_success "YooKassa Proxy установлен и запущен!"
echo
echo -e "${BLUE}📍 Endpoints:${NC}"
echo -e "  Proxy Health:  http://localhost:8888/health"
echo -e "  Public URL:    https://dagstatus.ru/yookassa/"
echo -e "  Webhook URL:   https://dagstatus.ru/yookassa/webhooks"
echo
echo -e "${BLUE}🔧 Управление:${NC}"
echo -e "  Статус:        docker logs yookassa-proxy"
echo -e "  Перезапуск:    cd $INSTALL_DIR && docker compose restart"
echo -e "  Остановка:     cd $INSTALL_DIR && docker compose down"
echo
echo -e "${BLUE}⚙️  Настройка YooKassa:${NC}"
echo -e "  1. Откройте: https://yookassa.ru/my/merchant/integration/notifications"
echo -e "  2. Добавьте webhook URL: ${BOLD}https://dagstatus.ru/yookassa/webhooks${NC}"
echo -e "  3. Выберите события: payment.succeeded, payment.canceled, refund.succeeded"
echo
log "Конфигурация сохранена в: $INSTALL_DIR/.env"
echo
