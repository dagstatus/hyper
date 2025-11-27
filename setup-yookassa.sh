#!/usr/bin/env bash
#
# Настройка YooKassa коннектора для Hyperswitch
# Требуется: Shop ID и Secret Key от YooKassa
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

API_URL="https://dagstatus.ru/api"
ADMIN_API_KEY=""

echo -e "${GREEN}${BOLD}"
cat << "EOF"
╔══════════════════════════════════════════════════════════════════════╗
║                                                                      ║
║         Настройка YooKassa для Hyperswitch                          ║
║                                                                      ║
╚══════════════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}\n"

# Получить Admin API Key
log "Получение Admin API Key..."
ADMIN_API_KEY=$(cat /opt/hyperswitch/.credentials | grep ADMIN_API_KEY | cut -d'=' -f2)

if [[ -z "$ADMIN_API_KEY" ]]; then
    log_error "Не удалось получить ADMIN_API_KEY"
    exit 1
fi

log_success "Admin API Key получен"

# Запросить данные YooKassa
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

# Создать merchant account (если не существует)
log "Создание merchant account..."

MERCHANT_RESPONSE=$(curl -s -X POST "${API_URL}/accounts" \
  -H "Content-Type: application/json" \
  -H "api-key: ${ADMIN_API_KEY}" \
  -d '{
    "merchant_id": "merchant_yookassa_'$(date +%s)'",
    "merchant_name": "YooKassa Merchant",
    "return_url": "https://dagstatus.ru/",
    "webhook_details": {
      "webhook_url": "https://dagstatus.ru/api/webhooks"
    },
    "metadata": {
      "connector": "yookassa"
    }
  }' 2>&1)

MERCHANT_ID=$(echo "$MERCHANT_RESPONSE" | jq -r '.merchant_id // empty')

if [[ -z "$MERCHANT_ID" ]]; then
    # Попробовать получить существующий merchant
    log_warning "Merchant account уже существует или ошибка создания"
    MERCHANT_ID="merchant_default"
else
    log_success "Merchant account создан: $MERCHANT_ID"
fi

# Создать merchant connector account для YooKassa
log "Настройка YooKassa коннектора..."

CONNECTOR_RESPONSE=$(curl -s -X POST "${API_URL}/account/${MERCHANT_ID}/connectors" \
  -H "Content-Type: application/json" \
  -H "api-key: ${ADMIN_API_KEY}" \
  -d "{
    \"connector_type\": \"fiz_operations\",
    \"connector_name\": \"yookassa\",
    \"connector_account_details\": {
      \"auth_type\": \"BodyKey\",
      \"api_key\": \"${YOOKASSA_SECRET_KEY}\",
      \"key1\": \"${YOOKASSA_SHOP_ID}\"
    },
    \"test_mode\": false,
    \"disabled\": false,
    \"payment_methods_enabled\": [
      {
        \"payment_method\": \"card\",
        \"payment_method_types\": [
          \"credit\",
          \"debit\"
        ]
      },
      {
        \"payment_method\": \"wallet\",
        \"payment_method_types\": [
          \"yandex_money\"
        ]
      }
    ],
    \"metadata\": {
      \"description\": \"YooKassa Payment Gateway\"
    }
  }")

CONNECTOR_ID=$(echo "$CONNECTOR_RESPONSE" | jq -r '.merchant_connector_id // empty')

if [[ -z "$CONNECTOR_ID" ]]; then
    log_error "Ошибка настройки YooKassa коннектора"
    echo "Ответ API: $CONNECTOR_RESPONSE" | jq '.' 2>/dev/null || echo "$CONNECTOR_RESPONSE"
    exit 1
fi

log_success "YooKassa коннектор настроен: $CONNECTOR_ID"

# Получить publishable key
log "Получение publishable key..."

PUBLISHABLE_KEY=$(curl -s -X GET "${API_URL}/accounts/${MERCHANT_ID}" \
  -H "api-key: ${ADMIN_API_KEY}" \
  | jq -r '.publishable_key // empty')

# Сохранить конфигурацию
cat > /opt/hyperswitch/yookassa-config.txt << EOF
╔══════════════════════════════════════════════════════════════════════╗
║                   YooKassa Configuration                             ║
╚══════════════════════════════════════════════════════════════════════╝

Merchant ID: ${MERCHANT_ID}
Connector ID: ${CONNECTOR_ID}
Publishable Key: ${PUBLISHABLE_KEY}

API Endpoint: ${API_URL}

Для тестирования используйте:
curl -X POST "${API_URL}/payments" \\
  -H "Content-Type: application/json" \\
  -H "api-key: ${PUBLISHABLE_KEY}" \\
  -d '{
    "amount": 10000,
    "currency": "RUB",
    "confirm": false,
    "capture_method": "automatic",
    "customer_id": "customer_test",
    "email": "test@example.com",
    "description": "Test payment"
  }'

EOF

cat /opt/hyperswitch/yookassa-config.txt

log_success "Конфигурация сохранена в /opt/hyperswitch/yookassa-config.txt"
echo
log_success "YooKassa успешно настроена!"
echo
