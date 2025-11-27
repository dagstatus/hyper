#!/usr/bin/env bash
#
# Автоматическое развертывание Hyperswitch Full Setup на Debian 11
# Версия: 1.0.0
# Автор: Deployment Script
#

set -euo pipefail

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Переменные конфигурации
INSTALL_DIR="/opt/hyperswitch"
BACKUP_DIR="/var/backups/hyperswitch"
LOG_FILE="/var/log/hyperswitch-install.log"
COMPOSE_PROJECT_NAME="hyperswitch"

# Флаги установки
INSTALL_NGINX=false
INSTALL_SSL=false
SETUP_FIREWALL=false
SETUP_BACKUP=false
DOMAIN_NAME=""

# =============================================================================
# Функции вывода
# =============================================================================

log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗ ОШИБКА:${NC} $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠ ПРЕДУПРЕЖДЕНИЕ:${NC} $1" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${CYAN}ℹ${NC} $1" | tee -a "$LOG_FILE"
}

show_banner() {
    clear
    echo -e "${BLUE}${BOLD}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║     HYPERSWITCH - Автоматическое развертывание (Full Setup)         ║
║                                                                      ║
║     Композитная платежная инфраструктура с открытым кодом           ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"
}

# =============================================================================
# Функции проверки
# =============================================================================

check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Этот скрипт НЕ должен запускаться от root!"
        log_info "Используйте обычного пользователя с sudo правами."
        exit 1
    fi

    # Проверка sudo прав
    if ! sudo -n true 2>/dev/null; then
        log_info "Введите пароль для sudo доступа:"
        sudo -v
    fi
}

check_os() {
    log "Проверка операционной системы..."

    if [[ ! -f /etc/os-release ]]; then
        log_error "Не удалось определить ОС"
        exit 1
    fi

    . /etc/os-release

    if [[ "$ID" != "debian" ]]; then
        log_warning "Обнаружена ОС: $ID. Скрипт оптимизирован для Debian 11."
        read -p "Продолжить? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    log_success "ОС: $PRETTY_NAME"
}

check_system_resources() {
    log "Проверка системных ресурсов..."

    # Проверка RAM
    total_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $total_ram -lt 4 ]]; then
        log_warning "Обнаружено ${total_ram}GB RAM. Рекомендуется минимум 4GB."
    else
        log_success "RAM: ${total_ram}GB"
    fi

    # Проверка свободного места на диске
    free_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $free_space -lt 20 ]]; then
        log_warning "Свободно ${free_space}GB. Рекомендуется минимум 20GB."
    else
        log_success "Свободное место: ${free_space}GB"
    fi

    # Проверка CPU
    cpu_cores=$(nproc)
    log_success "CPU ядер: $cpu_cores"
}

check_ports() {
    log "Проверка доступности портов..."

    required_ports=(8080 9000 9050 5432 6379 3000 9090)
    busy_ports=()

    for port in "${required_ports[@]}"; do
        if sudo lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 || \
           sudo ss -tuln | grep -q ":$port "; then
            busy_ports+=("$port")
        fi
    done

    if [[ ${#busy_ports[@]} -gt 0 ]]; then
        log_warning "Следующие порты уже заняты: ${busy_ports[*]}"
        read -p "Продолжить установку? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        log_success "Все необходимые порты свободны"
    fi
}

# =============================================================================
# Функции установки
# =============================================================================

install_dependencies() {
    log "Установка базовых зависимостей..."

    sudo apt-get update -qq
    sudo apt-get install -y -qq \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        git \
        jq \
        wget \
        ufw \
        net-tools \
        htop \
        nano \
        vim \
        2>&1 | tee -a "$LOG_FILE"

    log_success "Базовые зависимости установлены"
}

install_docker() {
    log "Проверка установки Docker..."

    if command -v docker &> /dev/null; then
        log_success "Docker уже установлен: $(docker --version)"
        return 0
    fi

    log "Установка Docker..."

    # Удаление старых версий
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

    # Добавление GPG ключа Docker
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Добавление репозитория Docker
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/debian \
        $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Установка Docker Engine
    sudo apt-get update -qq
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin 2>&1 | tee -a "$LOG_FILE"

    # Добавление текущего пользователя в группу docker
    sudo usermod -aG docker "$USER"

    # Включение автозапуска Docker
    sudo systemctl enable docker
    sudo systemctl start docker

    log_success "Docker установлен: $(docker --version)"
    log_success "Docker Compose установлен: $(docker compose version)"
    log_info "ВАЖНО: Выполните 'newgrp docker' или перелогиньтесь для применения прав группы docker"
}

clone_repository() {
    log "Клонирование репозитория Hyperswitch..."

    if [[ -d "$INSTALL_DIR" ]]; then
        log_warning "Директория $INSTALL_DIR уже существует"
        read -p "Удалить и клонировать заново? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo rm -rf "$INSTALL_DIR"
        else
            log_info "Используется существующая директория"
            return 0
        fi
    fi

    sudo mkdir -p "$INSTALL_DIR"
    sudo chown "$USER":"$USER" "$INSTALL_DIR"

    git clone --depth 1 --branch latest \
        https://github.com/juspay/hyperswitch "$INSTALL_DIR" 2>&1 | tee -a "$LOG_FILE"

    log_success "Репозиторий клонирован в $INSTALL_DIR"
}

configure_hyperswitch() {
    log "Настройка конфигурации Hyperswitch..."

    cd "$INSTALL_DIR"

    # Генерация безопасных ключей
    ADMIN_API_KEY=$(openssl rand -base64 32)
    JWT_SECRET=$(openssl rand -base64 32)
    MASTER_ENC_KEY=$(openssl rand -hex 32)

    # Генерация случайного пароля для БД
    DB_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-20)

    log_info "Сгенерированы безопасные ключи"

    # Сохранение учетных данных
    cat > "$INSTALL_DIR/.credentials" << EOF
# Учетные данные Hyperswitch
# Дата создания: $(date)
# ВАЖНО: Храните этот файл в безопасности!

ADMIN_API_KEY=$ADMIN_API_KEY
JWT_SECRET=$JWT_SECRET
MASTER_ENC_KEY=$MASTER_ENC_KEY
DB_PASSWORD=$DB_PASSWORD

# Доступ к Control Center:
# Email: demo@hyperswitch.com
# Password: Hyperswitch@123
EOF

    chmod 600 "$INSTALL_DIR/.credentials"

    # Создание файла окружения для Docker Compose
    cat > "$INSTALL_DIR/.env" << EOF
# Hyperswitch Environment Configuration
ONE_CLICK_SETUP=true
COMPOSE_PROJECT_NAME=$COMPOSE_PROJECT_NAME

# Database
POSTGRES_USER=db_user
POSTGRES_PASSWORD=$DB_PASSWORD
POSTGRES_DB=hyperswitch_db

# Redis
REDIS_CLUSTER_COUNT=3
DRAINER_INSTANCE_COUNT=1
EOF

    # Обновление конфигурации docker_compose.toml
    if [[ -f "$INSTALL_DIR/config/docker_compose.toml" ]]; then
        # Создаем резервную копию
        cp "$INSTALL_DIR/config/docker_compose.toml" \
           "$INSTALL_DIR/config/docker_compose.toml.backup"

        # Обновляем пароли и ключи
        sed -i "s/password = \"db_pass\"/password = \"$DB_PASSWORD\"/" \
            "$INSTALL_DIR/config/docker_compose.toml"
        sed -i "s/admin_api_key = \"test_admin\"/admin_api_key = \"$ADMIN_API_KEY\"/" \
            "$INSTALL_DIR/config/docker_compose.toml"
        sed -i "s/jwt_secret = \"secret\"/jwt_secret = \"$JWT_SECRET\"/" \
            "$INSTALL_DIR/config/docker_compose.toml"
        sed -i "s/master_enc_key = \".*\"/master_enc_key = \"$MASTER_ENC_KEY\"/" \
            "$INSTALL_DIR/config/docker_compose.toml"
    fi

    log_success "Конфигурация настроена"
    log_info "Учетные данные сохранены в: $INSTALL_DIR/.credentials"
}

deploy_hyperswitch() {
    log "Развертывание Hyperswitch (Full Setup)..."

    cd "$INSTALL_DIR"

    # Применяем права группы docker для текущей сессии
    newgrp docker << EOFNG
    # Запуск Full Setup
    docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup up -d
EOFNG

    log "Ожидание запуска сервисов (это может занять несколько минут)..."
    sleep 30

    # Проверка статуса сервисов
    log_info "Статус сервисов:"
    docker compose ps

    # Ожидание готовности API
    max_attempts=30
    attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if curl -s http://localhost:8080/health > /dev/null 2>&1; then
            log_success "Hyperswitch API готов к работе"
            break
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done
    echo

    if [[ $attempt -eq $max_attempts ]]; then
        log_error "Не удалось дождаться запуска API"
        log_info "Проверьте логи: docker compose logs -f hyperswitch-server"
        return 1
    fi

    log_success "Hyperswitch Full Setup успешно развернут"
}

setup_firewall() {
    if [[ "$SETUP_FIREWALL" != "true" ]]; then
        return 0
    fi

    log "Настройка firewall (UFW)..."

    # Включение UFW
    sudo ufw --force enable

    # Базовая политика
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # Разрешение SSH
    sudo ufw allow 22/tcp comment 'SSH'

    # Разрешение HTTP/HTTPS
    sudo ufw allow 80/tcp comment 'HTTP'
    sudo ufw allow 443/tcp comment 'HTTPS'

    if [[ "$INSTALL_NGINX" != "true" ]]; then
        # Если нет Nginx, открываем прямой доступ к сервисам
        sudo ufw allow 8080/tcp comment 'Hyperswitch API'
        sudo ufw allow 9000/tcp comment 'Control Center'
        sudo ufw allow 9050/tcp comment 'Web SDK'
        sudo ufw allow 3000/tcp comment 'Grafana'
    fi

    sudo ufw reload

    log_success "Firewall настроен"
    log_info "Статус firewall:"
    sudo ufw status numbered
}

install_nginx_reverse_proxy() {
    if [[ "$INSTALL_NGINX" != "true" ]]; then
        return 0
    fi

    log "Установка и настройка Nginx..."

    sudo apt-get install -y nginx 2>&1 | tee -a "$LOG_FILE"

    # Создание конфигурации Nginx
    sudo tee /etc/nginx/sites-available/hyperswitch > /dev/null << 'EOF'
# Hyperswitch Nginx Configuration

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

# Основной сервер
server {
    listen 80;
    server_name _;

    # Логи
    access_log /var/log/nginx/hyperswitch-access.log;
    error_log /var/log/nginx/hyperswitch-error.log;

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
EOF

    # Активация конфигурации
    sudo ln -sf /etc/nginx/sites-available/hyperswitch /etc/nginx/sites-enabled/
    sudo rm -f /etc/nginx/sites-enabled/default

    # Проверка конфигурации
    sudo nginx -t

    # Перезапуск Nginx
    sudo systemctl enable nginx
    sudo systemctl restart nginx

    log_success "Nginx установлен и настроен"
}

install_ssl_certificate() {
    if [[ "$INSTALL_SSL" != "true" ]] || [[ -z "$DOMAIN_NAME" ]]; then
        return 0
    fi

    log "Установка SSL сертификата для $DOMAIN_NAME..."

    sudo apt-get install -y certbot python3-certbot-nginx 2>&1 | tee -a "$LOG_FILE"

    # Обновление конфигурации с доменным именем
    sudo sed -i "s/server_name _;/server_name $DOMAIN_NAME;/" \
        /etc/nginx/sites-available/hyperswitch

    sudo nginx -t && sudo systemctl reload nginx

    # Получение сертификата
    sudo certbot --nginx -d "$DOMAIN_NAME" --non-interactive --agree-tos \
        --email "admin@$DOMAIN_NAME" --redirect

    # Автоматическое обновление сертификата
    sudo systemctl enable certbot.timer
    sudo systemctl start certbot.timer

    log_success "SSL сертификат установлен для $DOMAIN_NAME"
}

setup_systemd_service() {
    log "Настройка systemd службы для автозапуска..."

    sudo tee /etc/systemd/system/hyperswitch.service > /dev/null << EOF
[Unit]
Description=Hyperswitch Payment Infrastructure
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup up -d
ExecStop=/usr/bin/docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup down
User=$USER
Group=docker

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable hyperswitch.service

    log_success "Systemd служба настроена"
}

setup_backup_cron() {
    if [[ "$SETUP_BACKUP" != "true" ]]; then
        return 0
    fi

    log "Настройка автоматического резервного копирования..."

    sudo mkdir -p "$BACKUP_DIR"
    sudo chown "$USER":"$USER" "$BACKUP_DIR"

    # Скрипт резервного копирования
    sudo tee /usr/local/bin/backup-hyperswitch.sh > /dev/null << EOF
#!/bin/bash
# Скрипт резервного копирования Hyperswitch

BACKUP_DIR="$BACKUP_DIR"
DATE=\$(date +%Y%m%d_%H%M%S)
INSTALL_DIR="$INSTALL_DIR"

# Резервная копия PostgreSQL
cd "\$INSTALL_DIR"
docker compose exec -T pg pg_dump -U db_user hyperswitch_db | \
    gzip > "\$BACKUP_DIR/hyperswitch_db_\$DATE.sql.gz"

# Резервная копия конфигурации
tar -czf "\$BACKUP_DIR/hyperswitch_config_\$DATE.tar.gz" \
    -C "\$INSTALL_DIR" config .env .credentials

# Удаление резервных копий старше 7 дней
find "\$BACKUP_DIR" -type f -name "*.gz" -mtime +7 -delete
find "\$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +7 -delete

echo "\$(date): Резервное копирование завершено" >> "\$BACKUP_DIR/backup.log"
EOF

    sudo chmod +x /usr/local/bin/backup-hyperswitch.sh

    # Добавление в crontab (ежедневно в 2:00 AM)
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup-hyperswitch.sh") | \
        crontab -

    log_success "Резервное копирование настроено (ежедневно в 2:00 AM)"
    log_info "Резервные копии сохраняются в: $BACKUP_DIR"
}

# =============================================================================
# Функция интерактивной настройки
# =============================================================================

interactive_setup() {
    echo
    log_info "=== Интерактивная настройка ==="
    echo

    # Nginx
    read -p "Установить Nginx в качестве reverse proxy? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        INSTALL_NGINX=true

        # SSL
        read -p "Настроить SSL сертификат (Let's Encrypt)? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            INSTALL_SSL=true
            read -p "Введите доменное имя (например, hyperswitch.example.com): " DOMAIN_NAME
        fi
    fi

    echo

    # Firewall
    read -p "Настроить firewall (UFW)? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        SETUP_FIREWALL=true
    fi

    echo

    # Backup
    read -p "Настроить автоматическое резервное копирование? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        SETUP_BACKUP=true
    fi

    echo
}

# =============================================================================
# Функция вывода информации после установки
# =============================================================================

show_installation_summary() {
    clear
    echo -e "${GREEN}${BOLD}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║              УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!                           ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}\n"

    log_success "Hyperswitch Full Setup успешно развернут!"
    echo

    # Определение URL
    local base_url="http://localhost"
    if [[ "$INSTALL_NGINX" == "true" ]] && [[ "$INSTALL_SSL" == "true" ]] && [[ -n "$DOMAIN_NAME" ]]; then
        base_url="https://$DOMAIN_NAME"
    elif [[ "$INSTALL_NGINX" == "true" ]] && [[ -n "$DOMAIN_NAME" ]]; then
        base_url="http://$DOMAIN_NAME"
    fi

    echo -e "${CYAN}${BOLD}📍 ДОСТУП К СЕРВИСАМ:${NC}"
    echo

    if [[ "$INSTALL_NGINX" == "true" ]]; then
        echo -e "  ${GREEN}Control Center:${NC}  $base_url/"
        echo -e "  ${GREEN}API Server:${NC}      $base_url/api/"
        echo -e "  ${GREEN}Web SDK:${NC}         $base_url/sdk/"
        echo -e "  ${GREEN}Grafana:${NC}         $base_url/grafana/"
    else
        local server_ip=$(hostname -I | awk '{print $1}')
        echo -e "  ${GREEN}Control Center:${NC}  http://$server_ip:9000"
        echo -e "  ${GREEN}API Server:${NC}      http://$server_ip:8080"
        echo -e "  ${GREEN}Web SDK:${NC}         http://$server_ip:9050"
        echo -e "  ${GREEN}Grafana:${NC}         http://$server_ip:3000"
    fi

    echo
    echo -e "${CYAN}${BOLD}🔑 УЧЕТНЫЕ ДАННЫЕ:${NC}"
    echo
    echo -e "  ${YELLOW}Control Center (веб-интерфейс):${NC}"
    echo -e "    Email:    demo@hyperswitch.com"
    echo -e "    Password: Hyperswitch@123"
    echo
    echo -e "  ${YELLOW}API ключи и секреты:${NC}"
    echo -e "    Сохранены в: ${BOLD}$INSTALL_DIR/.credentials${NC}"
    echo -e "    Команда для просмотра: ${BOLD}cat $INSTALL_DIR/.credentials${NC}"
    echo

    echo -e "${CYAN}${BOLD}🛠️  ПОЛЕЗНЫЕ КОМАНДЫ:${NC}"
    echo
    echo -e "  ${YELLOW}Управление сервисами:${NC}"
    echo -e "    Статус:       cd $INSTALL_DIR && docker compose ps"
    echo -e "    Логи:         cd $INSTALL_DIR && docker compose logs -f"
    echo -e "    Перезапуск:   cd $INSTALL_DIR && docker compose restart"
    echo -e "    Остановка:    sudo systemctl stop hyperswitch"
    echo -e "    Запуск:       sudo systemctl start hyperswitch"
    echo
    echo -e "  ${YELLOW}Проверка здоровья:${NC}"
    echo -e "    curl http://localhost:8080/health"
    echo -e "    curl http://localhost:8080/health/ready"
    echo

    if [[ "$SETUP_BACKUP" == "true" ]]; then
        echo -e "  ${YELLOW}Резервное копирование:${NC}"
        echo -e "    Автоматически: ежедневно в 2:00 AM"
        echo -e "    Вручную:       /usr/local/bin/backup-hyperswitch.sh"
        echo -e "    Расположение:  $BACKUP_DIR"
        echo
    fi

    echo -e "${CYAN}${BOLD}📚 ДОКУМЕНТАЦИЯ:${NC}"
    echo
    echo -e "  Официальная документация: ${BLUE}https://docs.hyperswitch.io${NC}"
    echo -e "  API Reference:            ${BLUE}https://api-reference.hyperswitch.io${NC}"
    echo -e "  Postman Collection:       ${BLUE}https://www.postman.com/hyperswitch${NC}"
    echo -e "  Slack Community:          ${BLUE}https://inviter.co/hyperswitch-slack${NC}"
    echo

    echo -e "${CYAN}${BOLD}⚠️  ВАЖНЫЕ ЗАМЕЧАНИЯ:${NC}"
    echo
    echo -e "  ${RED}1.${NC} Обязательно сохраните файл ${BOLD}$INSTALL_DIR/.credentials${NC}"
    echo -e "  ${RED}2.${NC} Смените пароль demo пользователя в Control Center"
    if [[ "$INSTALL_NGINX" != "true" ]]; then
        echo -e "  ${RED}3.${NC} Для production рекомендуется настроить Nginx + SSL"
    fi
    if [[ "$SETUP_FIREWALL" != "true" ]]; then
        echo -e "  ${RED}4.${NC} Для production рекомендуется настроить firewall"
    fi
    echo

    echo -e "${GREEN}${BOLD}Для применения прав группы docker выполните:${NC}"
    echo -e "  ${BOLD}newgrp docker${NC}"
    echo -e "  или перелогиньтесь в систему"
    echo

    log_info "Лог установки сохранен в: $LOG_FILE"
    echo
}

# =============================================================================
# Основная функция
# =============================================================================

main() {
    # Инициализация лог-файла
    sudo mkdir -p "$(dirname "$LOG_FILE")"
    sudo touch "$LOG_FILE"
    sudo chown "$USER":"$USER" "$LOG_FILE"

    show_banner

    log "Начало установки Hyperswitch Full Setup"
    log "Время начала: $(date)"
    echo

    # Проверки
    check_root
    check_os
    check_system_resources
    check_ports

    echo

    # Интерактивная настройка
    interactive_setup

    echo
    log "Начинаем установку..."
    echo

    # Установка
    install_dependencies
    install_docker
    clone_repository
    configure_hyperswitch

    # Применение прав docker для текущей сессии
    if ! groups | grep -q docker; then
        log_warning "Применяю права группы docker..."
        newgrp docker << 'EOFMAIN'

        # Продолжение установки в новой группе
        deploy_hyperswitch

EOFMAIN
    else
        deploy_hyperswitch
    fi

    setup_systemd_service
    install_nginx_reverse_proxy
    install_ssl_certificate
    setup_firewall
    setup_backup_cron

    log "Время окончания: $(date)"

    # Итоговая информация
    show_installation_summary
}

# =============================================================================
# Точка входа
# =============================================================================

# Обработка аргументов командной строки
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-nginx)
            INSTALL_NGINX=true
            shift
            ;;
        --with-ssl)
            INSTALL_SSL=true
            shift
            ;;
        --domain)
            DOMAIN_NAME="$2"
            shift 2
            ;;
        --with-firewall)
            SETUP_FIREWALL=true
            shift
            ;;
        --with-backup)
            SETUP_BACKUP=true
            shift
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --help)
            echo "Использование: $0 [ОПЦИИ]"
            echo
            echo "Опции:"
            echo "  --with-nginx          Установить Nginx reverse proxy"
            echo "  --with-ssl            Установить SSL сертификат (требует --domain)"
            echo "  --domain DOMAIN       Доменное имя для SSL"
            echo "  --with-firewall       Настроить UFW firewall"
            echo "  --with-backup         Настроить автоматическое резервное копирование"
            echo "  --install-dir DIR     Директория установки (по умолчанию: /opt/hyperswitch)"
            echo "  --help                Показать это сообщение"
            echo
            echo "Пример:"
            echo "  $0 --with-nginx --with-ssl --domain hyperswitch.example.com --with-firewall --with-backup"
            exit 0
            ;;
        *)
            log_error "Неизвестная опция: $1"
            echo "Используйте --help для справки"
            exit 1
            ;;
    esac
done

# Запуск основной функции
main

exit 0
