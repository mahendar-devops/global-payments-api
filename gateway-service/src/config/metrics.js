'use strict';

const promClient = require('prom-client');
const express    = require('express');

// ── Default Node.js metrics (event loop, GC, memory) ───────────────────────
promClient.collectDefaultMetrics({
  labels: {
    service:     'gateway-service',
    environment: process.env.NODE_ENV || 'local',
  },
});

// ── Custom Business Metrics ─────────────────────────────────────────────────

const httpRequestDuration = new promClient.Histogram({
  name:    'gateway_http_request_duration_seconds',
  help:    'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
});

const httpRequestTotal = new promClient.Counter({
  name:    'gateway_http_requests_total',
  help:    'Total HTTP requests received',
  labelNames: ['method', 'route', 'status_code'],
});

const proxyErrorTotal = new promClient.Counter({
  name:    'gateway_proxy_errors_total',
  help:    'Total upstream proxy errors',
  labelNames: ['upstream_service', 'error_type'],
});

const circuitBreakerState = new promClient.Gauge({
  name:    'gateway_circuit_breaker_state',
  help:    'Circuit breaker state: 0=closed, 1=open, 0.5=half-open',
  labelNames: ['service'],
});

// ── Middleware to record metrics on every request ───────────────────────────

const metricsMiddleware = (req, res, next) => {
  const startTime = Date.now();

  res.on('finish', () => {
    // Normalise route to avoid high cardinality (e.g. /api/v1/payments/:id)
    const route = req.route ? req.baseUrl + req.route.path : req.path;

    const labels = {
      method:      req.method,
      route:       route,
      status_code: res.statusCode,
    };

    const durationSeconds = (Date.now() - startTime) / 1000;
    httpRequestDuration.observe(labels, durationSeconds);
    httpRequestTotal.inc(labels);
  });

  next();
};

// ── /metrics endpoint ────────────────────────────────────────────────────────

const metricsRouter = express.Router();

metricsRouter.get('/', async (req, res) => {
  res.set('Content-Type', promClient.register.contentType);
  res.end(await promClient.register.metrics());
});

module.exports = {
  metricsMiddleware,
  metricsRouter,
  proxyErrorTotal,
  circuitBreakerState,
};
