#!/usr/bin/env bash
#
# Скрипт проверки состояния Hyperswitch
# Использование: ./check-health.sh
#

set -euo pipefail

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="${INSTALL_DIR:-/opt/hyperswitch}"

echo -e "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║     HYPERSWITCH - Проверка состояния системы             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}\n"

# Проверка существования директории
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo -e "${RED}✗ Hyperswitch не установлен в $INSTALL_DIR${NC}"
    exit 1
fi

cd "$INSTALL_DIR"

# 1. Проверка Docker
echo -e "${CYAN}[1] Проверка Docker...${NC}"
if command -v docker &> /dev/null; then
    echo -e "${GREEN}  ✓ Docker установлен: $(docker --version)${NC}"
    if docker compose version &> /dev/null; then
        echo -e "${GREEN}  ✓ Docker Compose установлен: $(docker compose version)${NC}"
    else
        echo -e "${RED}  ✗ Docker Compose не найден${NC}"
    fi
else
    echo -e "${RED}  ✗ Docker не установлен${NC}"
    exit 1
fi
echo

# 2. Статус контейнеров
echo -e "${CYAN}[2] Статус контейнеров...${NC}"
if docker compose ps --format json > /dev/null 2>&1; then
    running_count=$(docker compose ps --format json | jq -r '.State' | grep -c "running" || echo "0")
    total_count=$(docker compose ps --format json | wc -l)

    echo -e "${GREEN}  ✓ Запущено контейнеров: $running_count / $total_count${NC}"
    echo
    docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
else
    echo -e "${YELLOW}  ⚠ Не удалось получить статус контейнеров${NC}"
fi
echo

# 3. Проверка здоровья API
echo -e "${CYAN}[3] Проверка API Server...${NC}"
if curl -sf http://localhost:8080/health > /dev/null; then
    health=$(curl -s http://localhost:8080/health)
    echo -e "${GREEN}  ✓ API Health: $health${NC}"

    # Получение версии
    version=$(curl -sI http://localhost:8080 | grep -i x-hyperswitch-version | cut -d' ' -f2 | tr -d '\r')
    if [[ -n "$version" ]]; then
        echo -e "${GREEN}  ✓ Версия: $version${NC}"
    fi

    # Детальная проверка
    if curl -sf http://localhost:8080/health/ready > /dev/null; then
        ready_status=$(curl -s http://localhost:8080/health/ready | jq -r '.database // "N/A", .redis // "N/A"' 2>/dev/null || echo "N/A N/A")
        echo -e "${GREEN}  ✓ Ready check passed${NC}"
    else
        echo -e "${RED}  ✗ Ready check failed${NC}"
    fi
else
    echo -e "${RED}  ✗ API недоступен на http://localhost:8080${NC}"
fi
echo

# 4. Проверка PostgreSQL
echo -e "${CYAN}[4] Проверка PostgreSQL...${NC}"
if docker compose exec -T pg pg_isready -U db_user &> /dev/null; then
    echo -e "${GREEN}  ✓ PostgreSQL работает${NC}"

    # Размер базы данных
    db_size=$(docker compose exec -T pg psql -U db_user -d hyperswitch_db -t -c \
        "SELECT pg_size_pretty(pg_database_size('hyperswitch_db'));" 2>/dev/null | xargs || echo "N/A")
    echo -e "${GREEN}  ✓ Размер БД: $db_size${NC}"

    # Количество подключений
    connections=$(docker compose exec -T pg psql -U db_user -d hyperswitch_db -t -c \
        "SELECT count(*) FROM pg_stat_activity WHERE datname='hyperswitch_db';" 2>/dev/null | xargs || echo "N/A")
    echo -e "${GREEN}  ✓ Активных подключений: $connections${NC}"
else
    echo -e "${RED}  ✗ PostgreSQL недоступен${NC}"
fi
echo

# 5. Проверка Redis
echo -e "${CYAN}[5] Проверка Redis...${NC}"
if docker compose exec -T redis-standalone redis-cli ping > /dev/null 2>&1; then
    echo -e "${GREEN}  ✓ Redis работает${NC}"

    # Информация о памяти
    used_memory=$(docker compose exec -T redis-standalone redis-cli info memory 2>/dev/null | \
        grep "used_memory_human" | cut -d: -f2 | tr -d '\r' || echo "N/A")
    echo -e "${GREEN}  ✓ Использовано памяти: $used_memory${NC}"

    # Количество ключей
    keys_count=$(docker compose exec -T redis-standalone redis-cli dbsize 2>/dev/null | tr -d '\r' || echo "N/A")
    echo -e "${GREEN}  ✓ Количество ключей: $keys_count${NC}"
else
    echo -e "${RED}  ✗ Redis недоступен${NC}"
fi
echo

# 6. Проверка доступности веб-интерфейсов
echo -e "${CYAN}[6] Проверка веб-интерфейсов...${NC}"

# Control Center
if curl -sf http://localhost:9000 > /dev/null; then
    echo -e "${GREEN}  ✓ Control Center доступен (http://localhost:9000)${NC}"
else
    echo -e "${YELLOW}  ⚠ Control Center недоступен${NC}"
fi

# Web SDK
if curl -sf http://localhost:9050 > /dev/null; then
    echo -e "${GREEN}  ✓ Web SDK доступен (http://localhost:9050)${NC}"
else
    echo -e "${YELLOW}  ⚠ Web SDK недоступен${NC}"
fi

# Grafana
if curl -sf http://localhost:3000 > /dev/null; then
    echo -e "${GREEN}  ✓ Grafana доступен (http://localhost:3000)${NC}"
else
    echo -e "${YELLOW}  ⚠ Grafana недоступен (возможно, не установлен Full Setup)${NC}"
fi
echo

# 7. Проверка использования ресурсов
echo -e "${CYAN}[7] Использование ресурсов...${NC}"
echo -e "${GREEN}  CPU и Memory по контейнерам:${NC}"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -n 10
echo

# 8. Проверка логов на ошибки
echo -e "${CYAN}[8] Последние ошибки в логах (за последний час)...${NC}"
error_count=$(docker compose logs --since 1h 2>&1 | grep -i "error\|fatal\|panic" | wc -l)
if [[ $error_count -eq 0 ]]; then
    echo -e "${GREEN}  ✓ Ошибок не обнаружено${NC}"
else
    echo -e "${YELLOW}  ⚠ Обнаружено ошибок: $error_count${NC}"
    echo -e "${YELLOW}  Последние 5 ошибок:${NC}"
    docker compose logs --since 1h 2>&1 | grep -i "error\|fatal\|panic" | tail -n 5
fi
echo

# 9. Проверка портов
echo -e "${CYAN}[9] Проверка прослушиваемых портов...${NC}"
required_ports=(8080 9000 9050 5432 6379)
for port in "${required_ports[@]}"; do
    if sudo lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 || \
       sudo ss -tuln | grep -q ":$port "; then
        service=$(sudo lsof -Pi :$port -sTCP:LISTEN | awk 'NR==2 {print $1}' || echo "unknown")
        echo -e "${GREEN}  ✓ Порт $port: активен ($service)${NC}"
    else
        echo -e "${RED}  ✗ Порт $port: не прослушивается${NC}"
    fi
done
echo

# 10. Проверка резервных копий
echo -e "${CYAN}[10] Резервные копии...${NC}"
if [[ -d "/var/backups/hyperswitch" ]]; then
    backup_count=$(find /var/backups/hyperswitch -type f -name "*.gz" 2>/dev/null | wc -l)
    if [[ $backup_count -gt 0 ]]; then
        latest_backup=$(ls -t /var/backups/hyperswitch/*.gz 2>/dev/null | head -n 1)
        backup_date=$(stat -c %y "$latest_backup" 2>/dev/null | cut -d' ' -f1 || echo "N/A")
        echo -e "${GREEN}  ✓ Найдено резервных копий: $backup_count${NC}"
        echo -e "${GREEN}  ✓ Последняя резервная копия: $backup_date${NC}"
    else
        echo -e "${YELLOW}  ⚠ Резервные копии не найдены${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ Директория резервных копий не существует${NC}"
fi
echo

# 11. Проверка systemd службы
echo -e "${CYAN}[11] Статус systemd службы...${NC}"
if systemctl is-active --quiet hyperswitch; then
    echo -e "${GREEN}  ✓ Служба hyperswitch активна${NC}"
    if systemctl is-enabled --quiet hyperswitch; then
        echo -e "${GREEN}  ✓ Автозапуск включен${NC}"
    else
        echo -e "${YELLOW}  ⚠ Автозапуск отключен${NC}"
    fi
else
    echo -e "${YELLOW}  ⚠ Служба hyperswitch неактивна${NC}"
fi
echo

# Итоговая оценка
echo -e "${BLUE}${BOLD}"
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                  ИТОГОВАЯ ОЦЕНКА                         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Подсчет статуса
api_ok=$(curl -sf http://localhost:8080/health > /dev/null && echo "1" || echo "0")
db_ok=$(docker compose exec -T pg pg_isready -U db_user &> /dev/null && echo "1" || echo "0")
redis_ok=$(docker compose exec -T redis-standalone redis-cli ping > /dev/null 2>&1 && echo "1" || echo "0")

total_score=$((api_ok + db_ok + redis_ok))

if [[ $total_score -eq 3 ]]; then
    echo -e "${GREEN}${BOLD}  ✓ Все основные компоненты работают нормально!${NC}"
    echo -e "${GREEN}  Система готова к работе.${NC}"
elif [[ $total_score -ge 2 ]]; then
    echo -e "${YELLOW}${BOLD}  ⚠ Система частично работоспособна${NC}"
    echo -e "${YELLOW}  Некоторые компоненты требуют внимания.${NC}"
else
    echo -e "${RED}${BOLD}  ✗ Обнаружены критические проблемы${NC}"
    echo -e "${RED}  Требуется немедленное вмешательство.${NC}"
fi

echo
echo -e "${CYAN}Для просмотра логов: ${BOLD}cd $INSTALL_DIR && docker compose logs -f${NC}"
echo -e "${CYAN}Для перезапуска: ${BOLD}sudo systemctl restart hyperswitch${NC}"
echo
