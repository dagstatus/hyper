# 🚀 Руководство по развертыванию Hyperswitch на Debian 11

## Быстрый старт

### Автоматическое развертывание (Full Setup)

```bash
# Скачайте и запустите скрипт установки
wget https://raw.githubusercontent.com/juspay/hyperswitch/main/deploy-debian11-full.sh
chmod +x deploy-debian11-full.sh
./deploy-debian11-full.sh
```

Скрипт автоматически:
- ✅ Проверит системные требования
- ✅ Установит Docker и Docker Compose
- ✅ Клонирует репозиторий Hyperswitch
- ✅ Сгенерирует безопасные ключи и пароли
- ✅ Развернет Full Setup (все сервисы + мониторинг)
- ✅ Настроит автозапуск через systemd
- ✅ Опционально настроит Nginx, SSL, Firewall, резервное копирование

---

## Варианты запуска

### 1. Интерактивный режим (рекомендуется)

```bash
./deploy-debian11-full.sh
```

Скрипт задаст вопросы:
- Установить Nginx?
- Настроить SSL?
- Настроить Firewall?
- Настроить резервное копирование?

### 2. С параметрами командной строки

```bash
# Полная установка с Nginx, SSL и всеми опциями
./deploy-debian11-full.sh \
  --with-nginx \
  --with-ssl \
  --domain hyperswitch.example.com \
  --with-firewall \
  --with-backup

# Базовая установка без дополнительных опций
./deploy-debian11-full.sh

# Установка только с Nginx (без SSL)
./deploy-debian11-full.sh --with-nginx

# Установка в пользовательскую директорию
./deploy-debian11-full.sh --install-dir /home/user/hyperswitch
```

### 3. Параметры командной строки

| Параметр | Описание |
|----------|----------|
| `--with-nginx` | Установить и настроить Nginx как reverse proxy |
| `--with-ssl` | Настроить SSL сертификат через Let's Encrypt |
| `--domain DOMAIN` | Доменное имя для SSL (например, hyperswitch.example.com) |
| `--with-firewall` | Настроить UFW firewall |
| `--with-backup` | Настроить автоматическое резервное копирование |
| `--install-dir DIR` | Директория установки (по умолчанию: /opt/hyperswitch) |
| `--help` | Показать справку |

---

## Системные требования

### Минимальные требования
- **ОС**: Debian 11 (рекомендуется) или совместимая
- **RAM**: 4GB (рекомендуется 8GB+)
- **Диск**: 20GB свободного места
- **CPU**: 2 ядра (рекомендуется 4+)
- **Сеть**: Стабильное интернет-соединение

### Необходимые порты
- **8080** - API Server
- **9000** - Control Center
- **9050** - Web SDK
- **3000** - Grafana (мониторинг)
- **5432** - PostgreSQL (внутренний)
- **6379** - Redis (внутренний)
- **9090** - Prometheus (внутренний)

### Для SSL сертификата
- Доменное имя, указывающее на ваш сервер
- Порты 80 и 443 должны быть открыты

---

## Что включает Full Setup

### Основные сервисы
- **Hyperswitch Router** - Основной API сервер
- **Control Center** - Веб-интерфейс управления
- **Web SDK** - SDK для интеграции платежей
- **PostgreSQL** - База данных
- **Redis** - Кэш и очередь сообщений

### Дополнительные компоненты
- **Scheduler (Producer + Consumer)** - Планировщик задач
- **Monitoring Stack**:
  - Grafana - Визуализация метрик
  - Prometheus - Сбор метрик
  - Loki - Агрегация логов
  - Tempo - Трассировка запросов
- **OLAP Stack** (аналитика):
  - Kafka - Очередь событий
  - ClickHouse - Аналитическая БД
  - OpenSearch - Поиск по логам

### Опциональные компоненты (устанавливаются при выборе)
- **Nginx** - Reverse proxy с балансировкой
- **SSL/TLS** - Шифрование трафика (Let's Encrypt)
- **UFW Firewall** - Защита портов
- **Автоматическое резервное копирование** - Ежедневные бэкапы БД

---

## После установки

### 1. Доступ к сервисам

#### Без Nginx (прямой доступ):
```
Control Center:  http://YOUR_SERVER_IP:9000
API Server:      http://YOUR_SERVER_IP:8080
Web SDK:         http://YOUR_SERVER_IP:9050
Grafana:         http://YOUR_SERVER_IP:3000
```

#### С Nginx (через reverse proxy):
```
Control Center:  http://YOUR_DOMAIN/
API Server:      http://YOUR_DOMAIN/api/
Web SDK:         http://YOUR_DOMAIN/sdk/
Grafana:         http://YOUR_DOMAIN/grafana/
```

#### С Nginx + SSL:
```
Control Center:  https://YOUR_DOMAIN/
API Server:      https://YOUR_DOMAIN/api/
Web SDK:         https://YOUR_DOMAIN/sdk/
Grafana:         https://YOUR_DOMAIN/grafana/
```

### 2. Учетные данные по умолчанию

**Control Center (веб-интерфейс):**
- Email: `demo@hyperswitch.com`
- Password: `Hyperswitch@123`

**API ключи и секреты:**
Сохранены в файле `/opt/hyperswitch/.credentials`

```bash
# Просмотр учетных данных
cat /opt/hyperswitch/.credentials
```

⚠️ **ВАЖНО**:
1. Сохраните файл `.credentials` в безопасном месте
2. Смените пароль demo пользователя после первого входа
3. Для production используйте собственные безопасные ключи

### 3. Проверка работоспособности

```bash
# Проверка статуса сервисов
cd /opt/hyperswitch
docker compose ps

# Проверка здоровья API
curl http://localhost:8080/health
# Ожидаемый ответ: "health is good"

# Детальная проверка
curl http://localhost:8080/health/ready | jq

# Просмотр логов
docker compose logs -f hyperswitch-server

# Просмотр логов всех сервисов
docker compose logs -f
```

---

## Управление сервисами

### Через systemd (автозапуск настроен)

```bash
# Статус
sudo systemctl status hyperswitch

# Запуск
sudo systemctl start hyperswitch

# Остановка
sudo systemctl stop hyperswitch

# Перезапуск
sudo systemctl restart hyperswitch

# Отключить автозапуск
sudo systemctl disable hyperswitch

# Включить автозапуск
sudo systemctl enable hyperswitch
```

### Через Docker Compose

```bash
cd /opt/hyperswitch

# Остановка всех сервисов
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup down

# Запуск всех сервисов
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup up -d

# Перезапуск конкретного сервиса
docker compose restart hyperswitch-server

# Просмотр логов
docker compose logs -f hyperswitch-server

# Статус сервисов
docker compose ps

# Просмотр ресурсов
docker stats
```

---

## Резервное копирование

### Автоматическое (если настроено)

Резервные копии создаются автоматически каждый день в 2:00 AM:
- База данных PostgreSQL (сжатый SQL dump)
- Конфигурационные файлы

```bash
# Расположение бэкапов
ls -lh /var/backups/hyperswitch/

# Просмотр лога резервного копирования
cat /var/backups/hyperswitch/backup.log
```

### Ручное резервное копирование

```bash
# Запуск скрипта резервного копирования
/usr/local/bin/backup-hyperswitch.sh

# Или через Docker Compose
cd /opt/hyperswitch
docker compose exec pg pg_dump -U db_user hyperswitch_db > backup_$(date +%Y%m%d).sql
```

### Восстановление из резервной копии

```bash
cd /opt/hyperswitch

# Распаковать бэкап
gunzip /var/backups/hyperswitch/hyperswitch_db_20250126_020000.sql.gz

# Восстановить базу данных
cat /var/backups/hyperswitch/hyperswitch_db_20250126_020000.sql | \
  docker compose exec -T pg psql -U db_user hyperswitch_db
```

---

## Обновление Hyperswitch

```bash
cd /opt/hyperswitch

# Остановка сервисов
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup down

# Создание резервной копии
/usr/local/bin/backup-hyperswitch.sh

# Обновление кода
git pull origin latest

# Запуск обновленных сервисов
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup pull
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup up -d

# Проверка обновления
curl -I http://localhost:8080 | grep x-hyperswitch-version
```

---

## Мониторинг

### Grafana

Доступ: `http://YOUR_SERVER_IP:3000` или `https://YOUR_DOMAIN/grafana/`

**Учетные данные** (анонимный доступ включен):
- Автоматический вход с правами Admin

**Доступные дашборды:**
- Метрики приложения
- Производительность API
- Статистика платежей
- Метрики базы данных и Redis

### Prometheus

Доступ: `http://localhost:9090` (только локально)

Метрики приложения доступны для запросов в Prometheus.

### Логи

```bash
# Просмотр логов всех сервисов
cd /opt/hyperswitch
docker compose logs -f

# Логи конкретного сервиса
docker compose logs -f hyperswitch-server
docker compose logs -f pg
docker compose logs -f redis-standalone
docker compose logs -f grafana

# Последние 100 строк
docker compose logs --tail=100 hyperswitch-server

# Логи за определенное время
docker compose logs --since 30m hyperswitch-server
```

---

## Настройка производительности

### Масштабирование

```bash
cd /opt/hyperswitch

# Увеличить количество инстансов drainer
echo "DRAINER_INSTANCE_COUNT=3" >> .env
docker compose --profile full_kv up -d --scale hyperswitch-drainer=3

# Настройка Redis cluster (для высоких нагрузок)
echo "REDIS_CLUSTER_COUNT=6" >> .env
docker compose --profile clustered_redis up -d
```

### Оптимизация PostgreSQL

```bash
# Увеличить pool_size в конфигурации
nano /opt/hyperswitch/config/docker_compose.toml

# Найти и изменить:
# [master_database]
# pool_size = 10  # Увеличить с 5 до 10

# Перезапустить
docker compose restart hyperswitch-server
```

---

## Безопасность

### 1. Смена учетных данных по умолчанию

```bash
cd /opt/hyperswitch
nano config/docker_compose.toml

# Измените:
# - admin_api_key
# - jwt_secret
# - master_enc_key
# - Пароли базы данных

# Перезапустите сервисы
docker compose restart
```

### 2. Настройка Firewall (если не настроено при установке)

```bash
# Включить UFW
sudo ufw enable

# Базовые правила
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Разрешить необходимые порты
sudo ufw allow 22/tcp   # SSH
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS

# Если НЕ используете Nginx, откройте порты сервисов:
sudo ufw allow 8080/tcp  # API
sudo ufw allow 9000/tcp  # Control Center
sudo ufw allow 3000/tcp  # Grafana

# Применить и проверить
sudo ufw reload
sudo ufw status
```

### 3. Настройка SSL (если не настроено при установке)

```bash
# Установить certbot
sudo apt install -y certbot python3-certbot-nginx

# Получить сертификат
sudo certbot --nginx -d your-domain.com

# Автообновление сертификата
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer
```

### 4. Ограничение доступа к PostgreSQL и Redis

По умолчанию PostgreSQL и Redis доступны только внутри Docker сети.
Для дополнительной безопасности можно убрать публикацию портов:

```bash
cd /opt/hyperswitch
nano docker-compose.yml

# Закомментируйте строки:
# pg:
#   ports:
#     - "5432:5432"  # Закомментировать эту строку
#
# redis-standalone:
#   ports:
#     - "6379:6379"  # Закомментировать эту строку

# Перезапустить
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup up -d
```

---

## Устранение неполадок

### Проблема: Сервисы не запускаются

```bash
# Проверить логи
cd /opt/hyperswitch
docker compose logs

# Проверить статус
docker compose ps

# Проверить занятые порты
sudo netstat -tulpn | grep -E ':(8080|9000|5432|6379)'

# Остановить конфликтующие сервисы
sudo systemctl stop postgresql
sudo systemctl stop redis-server
```

### Проблема: База данных недоступна

```bash
# Проверить статус PostgreSQL
docker compose ps pg

# Проверить логи
docker compose logs pg

# Перезапустить PostgreSQL
docker compose restart pg

# Подключиться к БД для диагностики
docker compose exec pg psql -U db_user hyperswitch_db
```

### Проблема: API возвращает ошибки

```bash
# Проверить логи роутера
docker compose logs -f hyperswitch-server

# Проверить здоровье
curl http://localhost:8080/health
curl http://localhost:8080/health/ready | jq

# Перезапустить роутер
docker compose restart hyperswitch-server
```

### Проблема: Нехватка места на диске

```bash
# Проверить использование диска
df -h

# Очистить неиспользуемые Docker образы и контейнеры
docker system prune -a

# Очистить старые логи
sudo journalctl --vacuum-time=7d

# Удалить старые резервные копии (старше 30 дней)
find /var/backups/hyperswitch -type f -mtime +30 -delete
```

### Проблема: Высокая нагрузка на CPU/RAM

```bash
# Проверить использование ресурсов
docker stats

# Ограничить ресурсы для контейнеров
cd /opt/hyperswitch
nano docker-compose.yml

# Добавить для сервисов:
# services:
#   hyperswitch-server:
#     deploy:
#       resources:
#         limits:
#           cpus: '2'
#           memory: 2G

# Перезапустить
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup up -d
```

---

## Удаление установки

```bash
# Остановить и удалить сервисы
cd /opt/hyperswitch
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup down -v

# Удалить systemd службу
sudo systemctl stop hyperswitch
sudo systemctl disable hyperswitch
sudo rm /etc/systemd/system/hyperswitch.service
sudo systemctl daemon-reload

# Удалить Nginx конфигурацию (если установлен)
sudo rm /etc/nginx/sites-enabled/hyperswitch
sudo rm /etc/nginx/sites-available/hyperswitch
sudo systemctl restart nginx

# Удалить cron задачу резервного копирования
crontab -l | grep -v backup-hyperswitch | crontab -

# Удалить файлы (ОСТОРОЖНО: удалит все данные!)
sudo rm -rf /opt/hyperswitch
sudo rm -rf /var/backups/hyperswitch
sudo rm /usr/local/bin/backup-hyperswitch.sh
sudo rm /var/log/hyperswitch-install.log

# Удалить Docker (опционально)
sudo apt-get remove -y docker-ce docker-ce-cli containerd.io
sudo rm -rf /var/lib/docker
```

---

## Полезные ссылки

- **Официальная документация**: https://docs.hyperswitch.io
- **API Reference**: https://api-reference.hyperswitch.io
- **GitHub**: https://github.com/juspay/hyperswitch
- **Postman Collection**: https://www.postman.com/hyperswitch/workspace/hyperswitch-development
- **Slack Community**: https://inviter.co/hyperswitch-slack
- **Видео-туториалы**: https://docs.hyperswitch.io/hyperswitch-open-source/overview/unified-local-setup-using-docker

---

## Поддержка

Если у вас возникли проблемы:

1. Проверьте логи: `docker compose logs -f`
2. Изучите документацию: https://docs.hyperswitch.io
3. Задайте вопрос в Slack: https://inviter.co/hyperswitch-slack
4. Создайте issue на GitHub: https://github.com/juspay/hyperswitch/issues

---

## Лицензия

Hyperswitch распространяется под лицензией Apache 2.0.
