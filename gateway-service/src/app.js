'use strict';

require('express-async-errors');
require('dotenv').config();

const express = require('express');
const helmet  = require('helmet');
const cors    = require('cors');
const morgan  = require('morgan');

const { logger, morganStream }  = require('./config/logger');
const { metricsMiddleware, metricsRouter } = require('./config/metrics');
const { globalErrorHandler }    = require('./middleware/errorHandler');
const { notFoundHandler }        = require('./middleware/errorHandler');
const rateLimiter                = require('./middleware/rateLimiter');
const requestIdMiddleware        = require('./middleware/requestId');
const paymentRoutes              = require('./routes/payments');
const healthRoutes               = require('./routes/health');

const app  = express();
const PORT = process.env.PORT || 3000;

// ── Security Headers ────────────────────────────────────────────────────────
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc:  ["'self'"],
      styleSrc:   ["'self'"],
      imgSrc:     ["'self'", 'data:'],
    },
  },
  hsts: {
    maxAge: 31536000,       // 1 year
    includeSubDomains: true,
    preload: true,
  },
}));

// ── CORS ────────────────────────────────────────────────────────────────────
const allowedOrigins = (process.env.ALLOWED_ORIGINS || 'http://localhost:3001').split(',');
app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (server-to-server, Postman)
    if (!origin || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      logger.warn(`CORS blocked for origin: ${origin}`);
      callback(new Error('Not allowed by CORS'));
    }
  },
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
  allowedHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key', 'X-Request-ID'],
  maxAge: 86400, // Cache preflight for 24 hours
}));

// ── Request Parsing ──────────────────────────────────────────────────────────
app.use(express.json({ limit: '100kb' }));  // Prevent large payload attacks
app.use(express.urlencoded({ extended: false }));

// ── Logging & Observability ──────────────────────────────────────────────────
app.use(requestIdMiddleware);     // Inject X-Request-ID on every request
app.use(morgan('combined', { stream: morganStream }));
app.use(metricsMiddleware);       // Prometheus request metrics

// ── Rate Limiting ────────────────────────────────────────────────────────────
// Applied to all API routes (not health/metrics)
app.use('/api', rateLimiter);

// ── Routes ───────────────────────────────────────────────────────────────────
app.use('/health',       healthRoutes);    // Kubernetes liveness/readiness
app.use('/metrics',      metricsRouter);   // Prometheus scrape endpoint
app.use('/api/v1',       paymentRoutes);   // Payment API (proxied to payments-service)

// ── Error Handling (must be last) ────────────────────────────────────────────
app.use(notFoundHandler);
app.use(globalErrorHandler);

// ── Start Server ─────────────────────────────────────────────────────────────
// Don't start server in test mode (supertest handles it)
if (process.env.NODE_ENV !== 'test') {
  const server = app.listen(PORT, () => {
    logger.info(`Gateway service started on port ${PORT}`, {
      environment: process.env.NODE_ENV,
      version:     process.env.npm_package_version,
    });
  });

  // Graceful shutdown — handle SIGTERM from Kubernetes
  const gracefulShutdown = (signal) => {
    logger.info(`${signal} received. Starting graceful shutdown...`);
    server.close(() => {
      logger.info('HTTP server closed. Exiting.');
      process.exit(0);
    });
    // Force exit after 30s if server hasn't closed
    setTimeout(() => {
      logger.error('Forced shutdown after timeout');
      process.exit(1);
    }, 30000);
  };

  process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
  process.on('SIGINT',  () => gracefulShutdown('SIGINT'));
}

module.exports = app;  // Export for testing
