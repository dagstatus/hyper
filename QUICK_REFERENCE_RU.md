# 📚 Hyperswitch - Краткая справка команд

## 🚀 Установка

```bash
# Скачать и запустить скрипт установки
wget https://raw.githubusercontent.com/juspay/hyperswitch/main/deploy-debian11-full.sh
chmod +x deploy-debian11-full.sh
./deploy-debian11-full.sh

# Полная установка с опциями
./deploy-debian11-full.sh --with-nginx --with-ssl --domain hyperswitch.example.com --with-firewall --with-backup
```

## 🔍 Проверка состояния

```bash
# Запустить скрипт проверки здоровья
./check-health.sh

# Быстрая проверка API
curl http://localhost:8080/health

# Детальная проверка
curl http://localhost:8080/health/ready | jq

# Проверка версии
curl -I http://localhost:8080 | grep x-hyperswitch-version
```

## 🎛️ Управление сервисами

### Через systemd
```bash
sudo systemctl status hyperswitch      # Статус
sudo systemctl start hyperswitch        # Запуск
sudo systemctl stop hyperswitch         # Остановка
sudo systemctl restart hyperswitch      # Перезапуск
sudo systemctl enable hyperswitch       # Включить автозапуск
sudo systemctl disable hyperswitch      # Отключить автозапуск
```

### Через Docker Compose
```bash
cd /opt/hyperswitch

# Статус контейнеров
docker compose ps

# Запуск Full Setup
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup up -d

# Остановка
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup down

# Перезапуск всех сервисов
docker compose restart

# Перезапуск конкретного сервиса
docker compose restart hyperswitch-server
docker compose restart pg
docker compose restart redis-standalone
```

## 📊 Логи

```bash
cd /opt/hyperswitch

# Все логи (real-time)
docker compose logs -f

# Логи конкретного сервиса
docker compose logs -f hyperswitch-server
docker compose logs -f pg
docker compose logs -f redis-standalone
docker compose logs -f grafana

# Последние 100 строк
docker compose logs --tail=100 hyperswitch-server

# Логи за последние 30 минут
docker compose logs --since 30m

# Поиск ошибок в логах
docker compose logs | grep -i error
docker compose logs --since 1h | grep -i "error\|fatal"
```

## 💾 Резервное копирование

```bash
# Автоматическое резервное копирование (если настроено)
/usr/local/bin/backup-hyperswitch.sh

# Ручная резервная копия БД
cd /opt/hyperswitch
docker compose exec pg pg_dump -U db_user hyperswitch_db > backup_$(date +%Y%m%d).sql

# Сжатая резервная копия
docker compose exec pg pg_dump -U db_user hyperswitch_db | gzip > backup_$(date +%Y%m%d).sql.gz

# Список резервных копий
ls -lh /var/backups/hyperswitch/

# Восстановление из резервной копии
gunzip backup_20250126.sql.gz
cat backup_20250126.sql | docker compose exec -T pg psql -U db_user hyperswitch_db
```

## 🗄️ Работа с базой данных

```bash
cd /opt/hyperswitch

# Подключение к PostgreSQL
docker compose exec pg psql -U db_user hyperswitch_db

# Выполнить SQL запрос
docker compose exec -T pg psql -U db_user hyperswitch_db -c "SELECT version();"

# Размер базы данных
docker compose exec -T pg psql -U db_user -d hyperswitch_db -c \
  "SELECT pg_size_pretty(pg_database_size('hyperswitch_db'));"

# Список таблиц
docker compose exec -T pg psql -U db_user -d hyperswitch_db -c "\dt"

# Количество записей в таблице
docker compose exec -T pg psql -U db_user -d hyperswitch_db -c \
  "SELECT count(*) FROM payment_intent;"
```

## 🔴 Работа с Redis

```bash
cd /opt/hyperswitch

# Подключение к Redis CLI
docker compose exec redis-standalone redis-cli

# Проверка соединения
docker compose exec redis-standalone redis-cli ping

# Информация о Redis
docker compose exec redis-standalone redis-cli info

# Количество ключей
docker compose exec redis-standalone redis-cli dbsize

# Использование памяти
docker compose exec redis-standalone redis-cli info memory

# Очистка всех ключей (ОСТОРОЖНО!)
docker compose exec redis-standalone redis-cli flushall
```

## 🔄 Обновление

```bash
cd /opt/hyperswitch

# Создать резервную копию перед обновлением
/usr/local/bin/backup-hyperswitch.sh

# Остановить сервисы
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup down

# Обновить код
git pull origin latest

# Скачать новые образы
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup pull

# Запустить обновленные сервисы
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup up -d

# Проверить версию
curl -I http://localhost:8080 | grep x-hyperswitch-version
```

## 🔧 Конфигурация

```bash
# Просмотр учетных данных
cat /opt/hyperswitch/.credentials

# Редактирование конфигурации
nano /opt/hyperswitch/config/docker_compose.toml

# Редактирование переменных окружения
nano /opt/hyperswitch/.env

# После изменения конфигурации - перезапуск
cd /opt/hyperswitch
docker compose restart
```

## 📈 Мониторинг ресурсов

```bash
# Использование ресурсов контейнерами
docker stats

# Использование ресурсов конкретным контейнером
docker stats hyperswitch-hyperswitch-server-1

# Использование диска
df -h
docker system df

# Использование сети
docker network inspect hyperswitch_router_net

# Очистка неиспользуемых ресурсов Docker
docker system prune -a
```

## 🌐 Сеть и порты

```bash
# Проверка открытых портов
sudo netstat -tulpn | grep -E ':(8080|9000|9050|5432|6379|3000)'

# Проверка доступности портов
nc -zv localhost 8080
nc -zv localhost 9000
nc -zv localhost 9050

# Список Docker сетей
docker network ls

# Детали сети Hyperswitch
docker network inspect hyperswitch_router_net
```

## 🔐 Firewall (UFW)

```bash
# Статус firewall
sudo ufw status numbered

# Разрешить порт
sudo ufw allow 8080/tcp

# Запретить порт
sudo ufw deny 8080/tcp

# Удалить правило (по номеру)
sudo ufw delete 1

# Перезагрузить firewall
sudo ufw reload
```

## 🌐 Nginx (если установлен)

```bash
# Проверка конфигурации
sudo nginx -t

# Перезапуск Nginx
sudo systemctl restart nginx

# Статус Nginx
sudo systemctl status nginx

# Логи Nginx
sudo tail -f /var/log/nginx/hyperswitch-access.log
sudo tail -f /var/log/nginx/hyperswitch-error.log

# Редактирование конфигурации
sudo nano /etc/nginx/sites-available/hyperswitch
```

## 🔒 SSL/TLS (Let's Encrypt)

```bash
# Получить новый сертификат
sudo certbot --nginx -d your-domain.com

# Обновить сертификат вручную
sudo certbot renew

# Список сертификатов
sudo certbot certificates

# Автоматическое обновление (проверка)
sudo systemctl status certbot.timer
```

## 🐛 Отладка

```bash
# Проверка процессов в контейнере
docker compose exec hyperswitch-server ps aux

# Вход в контейнер для отладки
docker compose exec hyperswitch-server /bin/bash

# Проверка переменных окружения в контейнере
docker compose exec hyperswitch-server env

# Проверка сетевого подключения из контейнера
docker compose exec hyperswitch-server curl http://localhost:8080/health

# Просмотр Docker событий
docker events
```

## 🧹 Очистка

```bash
# Остановить все контейнеры Hyperswitch
cd /opt/hyperswitch
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup down

# Остановить и удалить volumes (ОСТОРОЖНО: удалит данные!)
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup down -v

# Очистка неиспользуемых Docker ресурсов
docker system prune -a

# Очистка старых логов
sudo journalctl --vacuum-time=7d

# Очистка старых резервных копий (старше 30 дней)
find /var/backups/hyperswitch -type f -mtime +30 -delete
```

## 🧪 Тестирование

```bash
# Простой тест здоровья
curl http://localhost:8080/health

# Детальный тест
curl http://localhost:8080/health/ready | jq

# Тест с таймингом
curl -w "@-" -o /dev/null -s http://localhost:8080/health <<'EOF'
    time_namelookup:  %{time_namelookup}s\n
       time_connect:  %{time_connect}s\n
    time_appconnect:  %{time_appconnect}s\n
   time_pretransfer:  %{time_pretransfer}s\n
      time_redirect:  %{time_redirect}s\n
 time_starttransfer:  %{time_starttransfer}s\n
                    ----------\n
         time_total:  %{time_total}s\n
EOF

# Load testing (требует установки apache2-utils)
ab -n 100 -c 10 http://localhost:8080/health
```

## 📋 Системная информация

```bash
# Версия ОС
cat /etc/os-release

# Ресурсы системы
free -h              # RAM
df -h                # Диск
nproc                # CPU
uptime               # Время работы

# Docker версия
docker --version
docker compose version

# Версия Hyperswitch
curl -sI http://localhost:8080 | grep x-hyperswitch-version
```

## 🔗 Полезные URL

```bash
# Локальные (без Nginx)
Control Center:  http://localhost:9000
API:             http://localhost:8080
Web SDK:         http://localhost:9050
Grafana:         http://localhost:3000

# С Nginx
Control Center:  http://YOUR_DOMAIN/
API:             http://YOUR_DOMAIN/api/
Web SDK:         http://YOUR_DOMAIN/sdk/
Grafana:         http://YOUR_DOMAIN/grafana/
```

## 📞 Получение помощи

```bash
# Официальная документация
https://docs.hyperswitch.io

# API Reference
https://api-reference.hyperswitch.io

# GitHub Issues
https://github.com/juspay/hyperswitch/issues

# Slack Community
https://inviter.co/hyperswitch-slack

# Postman Collection
https://www.postman.com/hyperswitch/workspace/hyperswitch-development
```

---

## 🆘 Быстрое решение проблем

### Проблема: API не отвечает
```bash
docker compose logs -f hyperswitch-server
docker compose restart hyperswitch-server
curl http://localhost:8080/health
```

### Проблема: База данных недоступна
```bash
docker compose logs pg
docker compose restart pg
docker compose exec pg pg_isready -U db_user
```

### Проблема: Redis недоступен
```bash
docker compose logs redis-standalone
docker compose restart redis-standalone
docker compose exec redis-standalone redis-cli ping
```

### Проблема: Контейнеры не запускаются
```bash
docker compose ps
docker compose logs
sudo systemctl restart docker
docker compose --profile scheduler --profile monitoring --profile olap --profile full_setup up -d
```

### Проблема: Порты заняты
```bash
sudo netstat -tulpn | grep -E ':(8080|9000|5432|6379)'
sudo lsof -i :8080
# Остановите конфликтующий процесс
```

### Проблема: Нехватка места на диске
```bash
df -h
docker system prune -a
sudo journalctl --vacuum-time=7d
find /var/backups/hyperswitch -type f -mtime +30 -delete
```

---

**Совет**: Сохраните этот файл как закладку для быстрого доступа к командам!
