#!/usr/bin/env bash
#
# Автоматическое исправление ошибки "Invalid Host header" для sdk.dagstatus.ru
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

COMPOSE_DIR="/opt/hyperswitch"

echo -e "${GREEN}=== Исправление Invalid Host Header для SDK ===${NC}\n"

cd "$COMPOSE_DIR"

# Проверка наличия docker-compose.yml
if [[ ! -f "docker-compose.yml" ]]; then
    log_error "Файл docker-compose.yml не найден в $COMPOSE_DIR"
    exit 1
fi

log "Создание резервной копии docker-compose.yml..."
cp docker-compose.yml docker-compose.yml.backup.$(date +%Y%m%d_%H%M%S)
log_success "Резервная копия создана"

log "Обновление конфигурации hyperswitch-web..."

# Проверяем, есть ли уже DANGEROUSLY_DISABLE_HOST_CHECK
if grep -q "DANGEROUSLY_DISABLE_HOST_CHECK" docker-compose.yml; then
    log_success "Переменная DANGEROUSLY_DISABLE_HOST_CHECK уже установлена"
else
    # Добавляем переменную окружения для отключения проверки Host header
    # Ищем строку с ENV_BACKEND_URL и добавляем новые переменные после неё
    sed -i '/ENV_BACKEND_URL=http:\/\/localhost:8080/a\      - DANGEROUSLY_DISABLE_HOST_CHECK=true' docker-compose.yml

    log_success "Переменные окружения добавлены"
fi

log "Проверка изменений..."
echo -e "\n${YELLOW}Новые переменные окружения для hyperswitch-web:${NC}"
grep -A 10 "hyperswitch-web:" docker-compose.yml | grep -A 5 "environment:"

echo
read -p "Применить изменения и перезапустить контейнеры? (y/n): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Отменено пользователем"
    exit 0
fi

log "Остановка контейнеров..."
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup down

log "Запуск контейнеров с новой конфигурацией..."
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup up -d

log "Ожидание запуска сервисов..."
sleep 10

log "Проверка статуса контейнеров..."
docker compose ps | grep hyperswitch-web

echo
log_success "Готово! Проверьте https://sdk.dagstatus.ru/"
echo
echo -e "${YELLOW}Если ошибка осталась, попробуйте очистить кеш браузера или откройте в режиме инкогнито${NC}"
echo
