'use strict';

const { v4: uuidv4 } = require('uuid');
const { logger }     = require('../config/logger');

// ── Request ID Middleware ───────────────────────────────────────────────────

/**
 * Assigns a unique X-Request-ID to every request.
 * Propagated to upstream services for distributed tracing.
 */
const requestIdMiddleware = (req, res, next) => {
  const requestId = req.headers['x-request-id'] || uuidv4();
  req.requestId   = requestId;
  res.setHeader('X-Request-ID', requestId);
  next();
};

module.exports = requestIdMiddleware;
