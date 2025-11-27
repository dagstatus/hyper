#!/usr/bin/env bash
#
# Настройка поддоменов для Hyperswitch
# api.dagstatus.ru -> localhost:9000
# sdk.dagstatus.ru -> localhost:9050
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
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

echo -e "${GREEN}=== Настройка поддоменов Hyperswitch ===${NC}\n"

# Проверка DNS
log "Проверка DNS для поддоменов..."
API_DNS=$(dig +short api.dagstatus.ru | tail -n1)
SDK_DNS=$(dig +short sdk.dagstatus.ru | tail -n1)
SERVER_IP=$(ip addr show eth0 | grep "inet " | awk '{print $2}' | cut -d/ -f1)

if [[ -z "$API_DNS" ]]; then
    log_error "api.dagstatus.ru не резолвится!"
    log_warning "Добавьте A-запись: api.dagstatus.ru -> $SERVER_IP"
    exit 1
fi

if [[ -z "$SDK_DNS" ]]; then
    log_error "sdk.dagstatus.ru не резолвится!"
    log_warning "Добавьте A-запись: sdk.dagstatus.ru -> $SERVER_IP"
    exit 1
fi

log_success "DNS настроен: api=$API_DNS, sdk=$SDK_DNS"

# Копирование конфигураций (если они есть в текущей директории)
if [[ -f "api.dagstatus.ru.conf" ]]; then
    log "Установка конфигурации для api.dagstatus.ru..."
    sudo cp api.dagstatus.ru.conf /etc/nginx/sites-available/api.dagstatus.ru
    sudo ln -sf /etc/nginx/sites-available/api.dagstatus.ru /etc/nginx/sites-enabled/
    log_success "Конфигурация api установлена"
else
    log_warning "Файл api.dagstatus.ru.conf не найден в текущей директории"
    log_warning "Скопируйте файл на сервер и запустите скрипт заново"
    exit 1
fi

if [[ -f "sdk.dagstatus.ru.conf" ]]; then
    log "Установка конфигурации для sdk.dagstatus.ru..."
    sudo cp sdk.dagstatus.ru.conf /etc/nginx/sites-available/sdk.dagstatus.ru
    sudo ln -sf /etc/nginx/sites-available/sdk.dagstatus.ru /etc/nginx/sites-enabled/
    log_success "Конфигурация sdk установлена"
else
    log_warning "Файл sdk.dagstatus.ru.conf не найден в текущей директории"
    exit 1
fi

# Проверка конфигурации Nginx
log "Проверка конфигурации Nginx..."
sudo nginx -t

log "Перезагрузка Nginx..."
sudo systemctl reload nginx
log_success "Nginx перезагружен"

# Получение SSL сертификатов
log "Получение SSL сертификата для api.dagstatus.ru..."
sudo certbot --nginx -d api.dagstatus.ru \
    --non-interactive \
    --agree-tos \
    --email admin@dagstatus.ru \
    --redirect

log_success "SSL для api.dagstatus.ru установлен"

log "Получение SSL сертификата для sdk.dagstatus.ru..."
sudo certbot --nginx -d sdk.dagstatus.ru \
    --non-interactive \
    --agree-tos \
    --email admin@dagstatus.ru \
    --redirect

log_success "SSL для sdk.dagstatus.ru установлен"

# Итог
echo
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       Поддомены настроены успешно!                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo
echo -e "${BLUE}Доступные сервисы:${NC}"
echo -e "  ${GREEN}Control Center:${NC} https://dagstatus.ru/"
echo -e "  ${GREEN}API (port 9000):${NC} https://api.dagstatus.ru/"
echo -e "  ${GREEN}SDK:${NC}             https://sdk.dagstatus.ru/"
echo
log_success "Готово!"
