'use strict';

const { logger } = require('../config/logger');

/**
 * Global error handler. Must be last middleware in the chain.
 * Never exposes internal stack traces to clients.
 */
const globalErrorHandler = (err, req, res, next) => {
  const requestId = req.requestId || 'unknown';

  // Log full error internally
  logger.error('Unhandled error', {
    requestId,
    method:  req.method,
    path:    req.path,
    error:   err.message,
    stack:   err.stack,
  });

  // Map known error types to HTTP status codes
  let statusCode = err.statusCode || 500;
  let code       = err.code       || 'INTERNAL_ERROR';
  let message    = 'An unexpected error occurred. Reference: ' + requestId;

  if (err.name === 'ValidationError') {
    statusCode = 400;
    code       = 'VALIDATION_ERROR';
    message    = err.message;
  } else if (err.message === 'Not allowed by CORS') {
    statusCode = 403;
    code       = 'CORS_ERROR';
    message    = 'Cross-origin request not allowed';
  } else if (statusCode < 500) {
    // Client errors: safe to echo the message
    message = err.message;
  }

  res.status(statusCode).json({
    code,
    message,
    requestId,
    timestamp: new Date().toISOString(),
  });
};

const notFoundHandler = (req, res) => {
  res.status(404).json({
    code:      'NOT_FOUND',
    message:   `Route ${req.method} ${req.path} not found`,
    requestId: req.requestId,
    timestamp: new Date().toISOString(),
  });
};

module.exports = { globalErrorHandler, notFoundHandler };
