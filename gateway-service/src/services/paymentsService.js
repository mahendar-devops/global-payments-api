'use strict';

const axios   = require('axios');
const opossum = require('opossum');
const { logger } = require('../config/logger');
const { proxyErrorTotal, circuitBreakerState } = require('../config/metrics');

const PAYMENTS_SERVICE_URL = process.env.PAYMENTS_SERVICE_URL
  || 'http://payments-service.payments.svc.cluster.local:80';

// ── Axios client for payments-service ───────────────────────────────────────

const paymentsClient = axios.create({
  baseURL: PAYMENTS_SERVICE_URL,
  timeout: 10000,  // 10 second timeout
  headers: {
    'Content-Type': 'application/json',
    'Accept':       'application/json',
  },
});

// Request interceptor: log all outbound calls
paymentsClient.interceptors.request.use((config) => {
  logger.debug('Upstream request', {
    method:  config.method?.toUpperCase(),
    url:     config.baseURL + config.url,
    headers: { 'x-request-id': config.headers['x-request-id'] },
  });
  return config;
});

// Response interceptor: log and track errors
paymentsClient.interceptors.response.use(
  (response) => response,
  (error) => {
    const status = error.response?.status || 'network_error';
    logger.error('Upstream error', {
      service: 'payments-service',
      status,
      message: error.message,
    });
    proxyErrorTotal.inc({
      upstream_service: 'payments-service',
      error_type:       String(status),
    });
    return Promise.reject(error);
  }
);

// ── Circuit Breaker ──────────────────────────────────────────────────────────
// Prevents cascading failures: if payments-service is down,
// the circuit opens and the gateway returns a fast 503 instead of
// waiting for timeouts and exhausting the thread pool.

const circuitBreakerOptions = {
  timeout:            10000,  // Consider call failed if it takes > 10s
  errorThresholdPercentage: 50,  // Open circuit if 50% of calls fail
  resetTimeout:       30000,  // Try again after 30s (half-open state)
  volumeThreshold:    5,      // Minimum requests before tracking errors
};

const paymentsBreaker = new opossum(
  async (requestFn) => requestFn(),
  circuitBreakerOptions
);

paymentsBreaker.on('open',     () => {
  circuitBreakerState.set({ service: 'payments-service' }, 1);
  logger.warn('Circuit OPEN for payments-service — blocking requests');
});
paymentsBreaker.on('halfOpen', () => {
  circuitBreakerState.set({ service: 'payments-service' }, 0.5);
  logger.info('Circuit HALF-OPEN for payments-service — testing recovery');
});
paymentsBreaker.on('close',    () => {
  circuitBreakerState.set({ service: 'payments-service' }, 0);
  logger.info('Circuit CLOSED for payments-service — requests restored');
});

// ── Service Methods ──────────────────────────────────────────────────────────

const createPayment = async (payload, requestId, idempotencyKey) => {
  return paymentsBreaker.fire(async () => {
    const headers = buildHeaders(requestId, idempotencyKey);
    const response = await paymentsClient.post('/api/v1/payments', payload, { headers });
    return response.data;
  });
};

const getPaymentById = async (id, requestId) => {
  return paymentsBreaker.fire(async () => {
    const headers = buildHeaders(requestId);
    const response = await paymentsClient.get(`/api/v1/payments/${id}`, { headers });
    return response.data;
  });
};

const getPaymentByReference = async (reference, requestId) => {
  return paymentsBreaker.fire(async () => {
    const headers = buildHeaders(requestId);
    const response = await paymentsClient.get(`/api/v1/payments/ref/${reference}`, { headers });
    return response.data;
  });
};

const getPayments = async (senderAccountId, page, size, requestId) => {
  return paymentsBreaker.fire(async () => {
    const headers = buildHeaders(requestId);
    const response = await paymentsClient.get('/api/v1/payments', {
      params: { senderAccountId, page, size },
      headers,
    });
    return response.data;
  });
};

// ── Helpers ──────────────────────────────────────────────────────────────────

const buildHeaders = (requestId, idempotencyKey) => {
  const headers = { 'X-Request-ID': requestId };
  if (idempotencyKey) {
    headers['Idempotency-Key'] = idempotencyKey;
  }
  return headers;
};

/**
 * Map upstream Axios error to a gateway-friendly error with correct HTTP status.
 */
const mapUpstreamError = (err) => {
  if (paymentsBreaker.opened) {
    const cbError = new Error('Payment service temporarily unavailable. Please try again shortly.');
    cbError.statusCode = 503;
    cbError.code = 'SERVICE_UNAVAILABLE';
    return cbError;
  }

  if (!err.response) {
    const networkError = new Error('Unable to reach payment service');
    networkError.statusCode = 502;
    networkError.code = 'UPSTREAM_UNAVAILABLE';
    return networkError;
  }

  const upstreamError = new Error(err.response.data?.message || 'Upstream error');
  upstreamError.statusCode = err.response.status;
  upstreamError.code = err.response.data?.code || 'UPSTREAM_ERROR';
  return upstreamError;
};

module.exports = {
  createPayment,
  getPaymentById,
  getPaymentByReference,
  getPayments,
  mapUpstreamError,
};
