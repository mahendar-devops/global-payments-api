'use strict';

const rateLimit  = require('express-rate-limit');
const { v4: uuidv4 } = require('uuid');
const { logger } = require('../config/logger');

// ── Rate Limiter ────────────────────────────────────────────────────────────

/**
 * Global API rate limiter.
 * 100 requests per IP per minute.
 * In banking, this is a last-resort defence — primary rate limiting
 * is done at the AWS WAF layer.
 */
const rateLimiter = rateLimit({
  windowMs: 60 * 1000,      // 1 minute window
  max: 100,                  // 100 requests per IP per window
  standardHeaders: true,     // Return RateLimit-* headers
  legacyHeaders: false,
  message: {
    code:    'RATE_LIMIT_EXCEEDED',
    message: 'Too many requests. Please try again in a minute.',
  },
  skip: (req) => {
    // Don't rate-limit health checks or internal service traffic
    return req.path.startsWith('/health') || req.path.startsWith('/metrics');
  },
  keyGenerator: (req) => {
    // Use forwarded IP (behind ALB/proxy) if available
    return req.headers['x-forwarded-for']?.split(',')[0].trim() || req.ip;
  },
});

module.exports = rateLimiter;
