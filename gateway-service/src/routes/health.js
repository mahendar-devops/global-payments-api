'use strict';

const express = require('express');
const router  = express.Router();

let isReady = true; // Set to false during graceful shutdown

/**
 * Liveness probe — /health/liveness
 * Kubernetes will restart the pod if this returns non-2xx.
 * Only fail this if the process is in an unrecoverable state.
 */
router.get('/liveness', (req, res) => {
  res.json({
    status:  'UP',
    service: 'gateway-service',
    uptime:  process.uptime(),
    timestamp: new Date().toISOString(),
  });
});

/**
 * Readiness probe — /health/readiness
 * Kubernetes will stop routing traffic if this returns non-2xx.
 * Fail this if upstream dependencies are unavailable.
 */
router.get('/readiness', (req, res) => {
  if (!isReady) {
    return res.status(503).json({
      status:  'DOWN',
      reason:  'Service is shutting down',
      timestamp: new Date().toISOString(),
    });
  }

  // In production, you'd also check connectivity to payments-service here
  res.json({
    status:  'UP',
    service: 'gateway-service',
    timestamp: new Date().toISOString(),
  });
});

// Root health check for load balancer ping
router.get('/', (req, res) => res.json({ status: 'UP' }));

// Expose shutdown toggle for graceful shutdown
const setReady = (state) => { isReady = state; };

module.exports = router;
module.exports.setReady = setReady;
