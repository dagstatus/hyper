#!/usr/bin/env bash
#
# Автоматическое исправление URL для Control Center
# Меняет localhost на публичные домены
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

HYPERSWITCH_DIR="/opt/hyperswitch"
DASHBOARD_CONFIG="$HYPERSWITCH_DIR/config/dashboard.toml"

echo -e "${GREEN}=== Исправление API URLs для Control Center ===${NC}\n"

cd "$HYPERSWITCH_DIR"

# Проверка наличия файла конфигурации
if [[ ! -f "$DASHBOARD_CONFIG" ]]; then
    log_error "Файл $DASHBOARD_CONFIG не найден"
    exit 1
fi

log "Создание резервной копии dashboard.toml..."
cp "$DASHBOARD_CONFIG" "${DASHBOARD_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
log_success "Резервная копия создана"

log "Обновление URLs в dashboard.toml..."

# Заменяем localhost URL на публичные домены
sed -i 's|api_url="http://localhost:8080"|api_url="https://dagstatus.ru/api"|' "$DASHBOARD_CONFIG"
sed -i 's|sdk_url="http://localhost:9050/HyperLoader.js"|sdk_url="https://sdk.dagstatus.ru/HyperLoader.js"|' "$DASHBOARD_CONFIG"

log_success "URLs обновлены"

log "Новые настройки:"
grep -E "(api_url|sdk_url)" "$DASHBOARD_CONFIG"

echo
log "Перезапуск контейнеров..."
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup restart hyperswitch-control-center

log "Ожидание запуска Control Center..."
sleep 5

log_success "Готово!"
echo
echo -e "${GREEN}Новые URLs:${NC}"
echo -e "  API:  https://dagstatus.ru/api"
echo -e "  SDK:  https://sdk.dagstatus.ru/HyperLoader.js"
echo
echo -e "${YELLOW}Откройте https://dagstatus.ru/ и попробуйте авторизоваться снова${NC}"
echo -e "${YELLOW}Очистите кеш браузера (Ctrl+Shift+R) перед попыткой${NC}"
echo
