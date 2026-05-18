'use strict';

const jwt        = require('jsonwebtoken');
const { logger } = require('../config/logger');

/**
 * JWT Authentication Middleware.
 *
 * Validates the Bearer token from the Authorization header.
 * Attaches the decoded payload to req.user for downstream use.
 *
 * The gateway is the single entry point — it validates tokens once,
 * so downstream microservices (payments-service) can trust the
 * forwarded X-User-ID and X-User-Roles headers.
 */
const authenticate = (req, res, next) => {
  const authHeader = req.headers['authorization'];

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({
      code:    'UNAUTHORIZED',
      message: 'Authorization header missing or malformed',
    });
  }

  const token = authHeader.split(' ')[1];

  try {
    const secret  = process.env.JWT_SECRET;
    const decoded = jwt.verify(token, secret, {
      algorithms: ['HS256'],
      issuer:     process.env.JWT_ISSUER || 'global-payments-auth',
    });

    // Attach user context for downstream headers
    req.user = {
      id:    decoded.sub,
      email: decoded.email,
      roles: decoded.roles || [],
    };

    // Forward user context to upstream services as trusted headers
    // (downstream services trust these headers; they're set by the gateway only)
    req.headers['x-user-id']    = decoded.sub;
    req.headers['x-user-roles'] = (decoded.roles || []).join(',');
    req.headers['x-user-email'] = decoded.email;

    next();

  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      logger.warn('Expired JWT presented', { ip: req.ip });
      return res.status(401).json({
        code:    'TOKEN_EXPIRED',
        message: 'Your session has expired. Please log in again.',
      });
    }

    logger.warn('Invalid JWT presented', {
      ip:    req.ip,
      error: err.message,
    });

    return res.status(401).json({
      code:    'INVALID_TOKEN',
      message: 'Invalid authentication token',
    });
  }
};

/**
 * Role-based authorisation factory.
 * Usage: router.post('/payments', authenticate, requireRole('PAYMENT_INITIATOR'), handler)
 */
const requireRole = (...requiredRoles) => (req, res, next) => {
  if (!req.user) {
    return res.status(401).json({ code: 'UNAUTHORIZED', message: 'Not authenticated' });
  }

  const hasRole = requiredRoles.some(role => req.user.roles.includes(role));

  if (!hasRole) {
    logger.warn('Insufficient permissions', {
      userId:        req.user.id,
      requiredRoles,
      userRoles:     req.user.roles,
      path:          req.path,
    });
    return res.status(403).json({
      code:    'FORBIDDEN',
      message: `Required role: one of [${requiredRoles.join(', ')}]`,
    });
  }

  next();
};

module.exports = { authenticate, requireRole };
