const express = require('express');
const axios = require('axios');
const bodyParser = require('body-parser');
const { v4: uuidv4 } = require('uuid');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 8888;

// YooKassa API configuration
const YOOKASSA_API_URL = 'https://api.yookassa.ru/v3';
const SHOP_ID = process.env.YOOKASSA_SHOP_ID;
const SECRET_KEY = process.env.YOOKASSA_SECRET_KEY;

app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// Logging middleware
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  next();
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'yookassa-proxy' });
});

// Create payment
app.post('/payments', async (req, res) => {
  try {
    const {
      amount,
      currency,
      description,
      customer_id,
      email,
      return_url,
      metadata
    } = req.body;

    // Convert amount from cents to rubles
    const amountInRubles = (amount / 100).toFixed(2);

    // Create YooKassa payment
    const yookassaPayment = {
      amount: {
        value: amountInRubles,
        currency: currency || 'RUB'
      },
      confirmation: {
        type: 'redirect',
        return_url: return_url || process.env.DEFAULT_RETURN_URL
      },
      capture: true,
      description: description || 'Payment via Hyperswitch',
      metadata: {
        ...metadata,
        customer_id,
        email
      }
    };

    const response = await axios.post(
      `${YOOKASSA_API_URL}/payments`,
      yookassaPayment,
      {
        auth: {
          username: SHOP_ID,
          password: SECRET_KEY
        },
        headers: {
          'Idempotence-Key': uuidv4(),
          'Content-Type': 'application/json'
        }
      }
    );

    // Convert YooKassa response to Hyperswitch format
    const hyperswitchResponse = {
      payment_id: response.data.id,
      status: mapYooKassaStatus(response.data.status),
      amount: parseInt(response.data.amount.value * 100),
      currency: response.data.amount.currency,
      confirmation_url: response.data.confirmation?.confirmation_url,
      created_at: response.data.created_at,
      metadata: response.data.metadata
    };

    res.json(hyperswitchResponse);
  } catch (error) {
    console.error('Error creating payment:', error.response?.data || error.message);
    res.status(error.response?.status || 500).json({
      error: {
        message: error.response?.data?.description || 'Payment creation failed',
        code: error.response?.data?.code || 'UNKNOWN_ERROR'
      }
    });
  }
});

// Get payment status
app.get('/payments/:payment_id', async (req, res) => {
  try {
    const { payment_id } = req.params;

    const response = await axios.get(
      `${YOOKASSA_API_URL}/payments/${payment_id}`,
      {
        auth: {
          username: SHOP_ID,
          password: SECRET_KEY
        }
      }
    );

    // Convert YooKassa response to Hyperswitch format
    const hyperswitchResponse = {
      payment_id: response.data.id,
      status: mapYooKassaStatus(response.data.status),
      amount: parseInt(response.data.amount.value * 100),
      currency: response.data.amount.currency,
      paid: response.data.paid,
      created_at: response.data.created_at,
      captured_at: response.data.captured_at,
      metadata: response.data.metadata
    };

    res.json(hyperswitchResponse);
  } catch (error) {
    console.error('Error getting payment:', error.response?.data || error.message);
    res.status(error.response?.status || 500).json({
      error: {
        message: error.response?.data?.description || 'Payment retrieval failed',
        code: error.response?.data?.code || 'UNKNOWN_ERROR'
      }
    });
  }
});

// Cancel payment
app.post('/payments/:payment_id/cancel', async (req, res) => {
  try {
    const { payment_id } = req.params;

    const response = await axios.post(
      `${YOOKASSA_API_URL}/payments/${payment_id}/cancel`,
      {},
      {
        auth: {
          username: SHOP_ID,
          password: SECRET_KEY
        },
        headers: {
          'Idempotence-Key': uuidv4()
        }
      }
    );

    res.json({
      payment_id: response.data.id,
      status: mapYooKassaStatus(response.data.status),
      cancelled: true
    });
  } catch (error) {
    console.error('Error cancelling payment:', error.response?.data || error.message);
    res.status(error.response?.status || 500).json({
      error: {
        message: error.response?.data?.description || 'Payment cancellation failed',
        code: error.response?.data?.code || 'UNKNOWN_ERROR'
      }
    });
  }
});

// Create refund
app.post('/refunds', async (req, res) => {
  try {
    const { payment_id, amount, reason } = req.body;

    // Convert amount from cents to rubles
    const amountInRubles = (amount / 100).toFixed(2);

    const yookassaRefund = {
      payment_id,
      amount: {
        value: amountInRubles,
        currency: 'RUB'
      },
      description: reason || 'Refund via Hyperswitch'
    };

    const response = await axios.post(
      `${YOOKASSA_API_URL}/refunds`,
      yookassaRefund,
      {
        auth: {
          username: SHOP_ID,
          password: SECRET_KEY
        },
        headers: {
          'Idempotence-Key': uuidv4(),
          'Content-Type': 'application/json'
        }
      }
    );

    res.json({
      refund_id: response.data.id,
      payment_id: response.data.payment_id,
      status: response.data.status,
      amount: parseInt(response.data.amount.value * 100),
      created_at: response.data.created_at
    });
  } catch (error) {
    console.error('Error creating refund:', error.response?.data || error.message);
    res.status(error.response?.status || 500).json({
      error: {
        message: error.response?.data?.description || 'Refund creation failed',
        code: error.response?.data?.code || 'UNKNOWN_ERROR'
      }
    });
  }
});

// Webhook handler
app.post('/webhooks', async (req, res) => {
  try {
    const event = req.body;

    console.log('Received webhook:', JSON.stringify(event, null, 2));

    // Verify webhook signature if needed
    // TODO: Implement signature verification

    // Process different event types
    switch (event.event) {
      case 'payment.succeeded':
        console.log('Payment succeeded:', event.object.id);
        // Forward to Hyperswitch webhook
        await forwardToHyperswitch(event);
        break;

      case 'payment.canceled':
        console.log('Payment canceled:', event.object.id);
        await forwardToHyperswitch(event);
        break;

      case 'refund.succeeded':
        console.log('Refund succeeded:', event.object.id);
        await forwardToHyperswitch(event);
        break;

      default:
        console.log('Unknown event type:', event.event);
    }

    res.json({ received: true });
  } catch (error) {
    console.error('Error processing webhook:', error);
    res.status(500).json({ error: 'Webhook processing failed' });
  }
});

// Helper function to map YooKassa status to Hyperswitch status
function mapYooKassaStatus(yookassaStatus) {
  const statusMap = {
    'pending': 'processing',
    'waiting_for_capture': 'requires_capture',
    'succeeded': 'succeeded',
    'canceled': 'cancelled'
  };

  return statusMap[yookassaStatus] || 'processing';
}

// Helper function to forward webhook to Hyperswitch
async function forwardToHyperswitch(event) {
  try {
    const hyperswitchWebhookUrl = process.env.HYPERSWITCH_WEBHOOK_URL;

    if (!hyperswitchWebhookUrl) {
      console.warn('HYPERSWITCH_WEBHOOK_URL not configured, skipping forward');
      return;
    }

    await axios.post(hyperswitchWebhookUrl, {
      event_type: event.event,
      payment_id: event.object.id,
      status: mapYooKassaStatus(event.object.status),
      data: event.object
    });

    console.log('Webhook forwarded to Hyperswitch');
  } catch (error) {
    console.error('Error forwarding webhook:', error.message);
  }
}

app.listen(PORT, () => {
  console.log(`YooKassa Proxy Server running on port ${PORT}`);
  console.log(`Shop ID: ${SHOP_ID ? '***' + SHOP_ID.slice(-4) : 'NOT SET'}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});

module.exports = app;
