#!/usr/bin/env bash
#
# Исправление проксирования API в Nginx
# Убирает префикс /api при проксировании
#

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

NGINX_CONFIG="/etc/nginx/sites-available/dagstatus.ru"

echo -e "${GREEN}=== Исправление API proxy в Nginx ===${NC}\n"

# Проверка наличия конфигурации
if [[ ! -f "$NGINX_CONFIG" ]]; then
    log_error "Файл $NGINX_CONFIG не найден"
    exit 1
fi

log "Создание резервной копии конфигурации..."
sudo cp "$NGINX_CONFIG" "${NGINX_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
log_success "Резервная копия создана"

log "Обновление location /api..."

# Заменяем proxy_pass для API
# Добавляем rewrite для удаления префикса /api
sudo sed -i '/location \/api {/,/proxy_pass/ {
    s|proxy_pass http://hyperswitch_api;|rewrite ^/api/(.*) /$1 break;\n        proxy_pass http://hyperswitch_api;|
}' "$NGINX_CONFIG"

log_success "Конфигурация обновлена"

log "Проверка конфигурации Nginx..."
sudo nginx -t

if [ $? -eq 0 ]; then
    log_success "Конфигурация корректна"

    log "Перезагрузка Nginx..."
    sudo systemctl reload nginx
    log_success "Nginx перезагружен"

    echo
    log_success "Готово! Теперь /api/* будет проксироваться без префикса"
    echo
    echo -e "${YELLOW}Попробуйте авторизоваться на https://dagstatus.ru/ снова${NC}"
else
    log_error "Ошибка в конфигурации Nginx"
    log "Восстанавливаем из резервной копии..."
    sudo cp "${NGINX_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)" "$NGINX_CONFIG"
    exit 1
fi
