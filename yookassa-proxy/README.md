# YooKassa Proxy для Hyperswitch

Кастомная интеграция YooKassa через Custom Billing коннектор.

## Архитектура

```
[Hyperswitch] → [YooKassa Proxy] → [YooKassa API]
      ↓              ↓                    ↓
   Custom       Node.js/Express      https://api.yookassa.ru
   Billing        Port 8888
```

## Установка

### 1. Скопируйте файлы на сервер

```bash
# С вашего Mac:
cd /Users/timur/Documents/claude/hyperswitch
scp -r yookassa-proxy timur@45.156.21.104:/tmp/
scp setup-yookassa-proxy.sh timur@45.156.21.104:/tmp/
```

### 2. Запустите установку

```bash
# На сервере:
ssh timur@45.156.21.104
cd /tmp
chmod +x setup-yookassa-proxy.sh
./setup-yookassa-proxy.sh
```

Скрипт автоматически:
- ✅ Установит прокси-сервис
- ✅ Создаст Docker контейнер
- ✅ Настроит Nginx
- ✅ Настроит Custom Billing коннектор
- ✅ Выдаст webhook URL

### 3. Настройте webhooks в YooKassa

1. Откройте: https://yookassa.ru/my/merchant/integration/notifications
2. Добавьте HTTP URL: `https://dagstatus.ru/yookassa/webhooks`
3. Выберите события:
   - ✅ `payment.succeeded` - успешная оплата
   - ✅ `payment.canceled` - отмена платежа
   - ✅ `refund.succeeded` - возврат выполнен

## API Endpoints

### Создать платёж

```bash
POST https://dagstatus.ru/yookassa/payments
Content-Type: application/json

{
  "amount": 10000,           # В копейках (100.00 руб)
  "currency": "RUB",
  "description": "Оплата заказа #123",
  "customer_id": "customer_1",
  "email": "customer@example.com",
  "return_url": "https://yoursite.com/success"
}
```

### Получить статус платежа

```bash
GET https://dagstatus.ru/yookassa/payments/{payment_id}
```

### Отменить платёж

```bash
POST https://dagstatus.ru/yookassa/payments/{payment_id}/cancel
```

### Создать возврат

```bash
POST https://dagstatus.ru/yookassa/refunds
Content-Type: application/json

{
  "payment_id": "2b5ee842-000f-5000-8000-1d8de7ab3ec8",
  "amount": 10000,
  "reason": "Возврат по запросу клиента"
}
```

## Тестирование

### 1. Проверка работоспособности

```bash
# Health check
curl https://dagstatus.ru/yookassa/health

# Должен вернуть:
# {"status":"ok","service":"yookassa-proxy"}
```

### 2. Тестовый платёж

```bash
curl -X POST https://dagstatus.ru/yookassa/payments \
  -H "Content-Type: application/json" \
  -d '{
    "amount": 10000,
    "currency": "RUB",
    "description": "Тестовый платёж",
    "customer_id": "test_customer",
    "email": "test@example.com",
    "return_url": "https://dagstatus.ru/"
  }'
```

### 3. Тестовые карты

**Успешная оплата:**
```
Номер: 5555 5555 5555 4477
Срок: 12/25
CVC: 123
```

**Отклоненный платёж:**
```
Номер: 5555 5555 5555 5599
Срок: 12/25
CVC: 123
```

## Управление

### Просмотр логов

```bash
docker logs -f yookassa-proxy
```

### Перезапуск

```bash
cd /opt/yookassa-proxy
docker compose restart
```

### Остановка

```bash
cd /opt/yookassa-proxy
docker compose down
```

### Обновление конфигурации

```bash
nano /opt/yookassa-proxy/.env
docker compose restart
```

## Интеграция с Hyperswitch

После установки YooKassa будет доступна в Hyperswitch как Custom Billing коннектор.

### Использование через Hyperswitch API

```bash
# Создать платёж через Hyperswitch
curl -X POST https://dagstatus.ru/api/payments \
  -H "Content-Type: application/json" \
  -H "api-key: YOUR_PUBLISHABLE_KEY" \
  -d '{
    "amount": 10000,
    "currency": "RUB",
    "connector": ["custombilling"],
    "customer_id": "customer_1",
    "description": "Оплата через YooKassa"
  }'
```

## Безопасность

- ✅ HTTPS обязателен
- ✅ Секретные ключи хранятся в .env (chmod 600)
- ✅ Basic Auth для YooKassa API
- ✅ Webhook signature verification (рекомендуется)

## Troubleshooting

### Проблема: 502 Bad Gateway

```bash
# Проверить статус контейнера
docker ps | grep yookassa-proxy

# Перезапустить
cd /opt/yookassa-proxy && docker compose restart
```

### Проблема: Invalid credentials

```bash
# Проверить учётные данные
cat /opt/yookassa-proxy/.env | grep YOOKASSA

# Обновить и перезапустить
nano /opt/yookassa-proxy/.env
docker compose restart
```

### Проблема: Webhook не приходят

1. Проверьте URL в YooKassa: `https://dagstatus.ru/yookassa/webhooks`
2. Убедитесь, что firewall разрешает входящие на 443 порт
3. Проверьте логи: `docker logs yookassa-proxy | grep webhook`

## Поддержка

- Документация YooKassa: https://yookassa.ru/developers/api
- Личный кабинет: https://yookassa.ru/my
- Тестовая среда: https://yookassa.ru/developers/using-api/testing
