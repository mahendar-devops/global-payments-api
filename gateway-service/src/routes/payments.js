'use strict';

const express     = require('express');
const { body, param, query, validationResult } = require('express-validator');
const { authenticate, requireRole } = require('../middleware/auth');
const paymentsService = require('../services/paymentsService');
const { logger }  = require('../config/logger');

const router = express.Router();

// ── Validation Middleware Helper ─────────────────────────────────────────────

const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    return res.status(400).json({
      code:        'VALIDATION_ERROR',
      message:     'Request validation failed',
      fieldErrors: errors.array().reduce((acc, err) => {
        acc[err.path] = err.msg;
        return acc;
      }, {}),
      requestId: req.requestId,
    });
  }
  next();
};

// ── POST /api/v1/payments ────────────────────────────────────────────────────

router.post(
  '/payments',
  authenticate,
  requireRole('PAYMENT_INITIATOR', 'ADMIN'),

  // Input validation at the gateway level (before hitting the upstream service)
  body('senderAccountId')
    .trim().notEmpty().withMessage('senderAccountId is required')
    .isLength({ max: 34 }).withMessage('senderAccountId must not exceed 34 characters'),
  body('receiverAccountId')
    .trim().notEmpty().withMessage('receiverAccountId is required')
    .isLength({ max: 34 }),
  body('receiverBankCode')
    .trim().notEmpty().withMessage('receiverBankCode is required')
    .isLength({ min: 8, max: 11 }).withMessage('receiverBankCode must be 8-11 characters'),
  body('amount')
    .isDecimal({ decimal_digits: '1,2' }).withMessage('amount must be a decimal with up to 2 places')
    .custom(val => parseFloat(val) > 0).withMessage('amount must be greater than 0')
    .custom(val => parseFloat(val) <= 1000000).withMessage('amount exceeds single-transaction limit'),
  body('currency')
    .notEmpty().isIn(['GBP','USD','EUR','JPY','CHF','CAD','AUD','SGD','HKD','INR']),
  body('paymentType')
    .notEmpty().isIn(['DOMESTIC','SEPA','SWIFT']),
  body('description')
    .optional().trim().isLength({ max: 140 }),
  validate,

  async (req, res, next) => {
    try {
      const idempotencyKey = req.headers['idempotency-key'];

      logger.info('Creating payment', {
        requestId:       req.requestId,
        userId:          req.user.id,
        senderAccountId: req.body.senderAccountId,
        amount:          req.body.amount,
        currency:        req.body.currency,
      });

      const payment = await paymentsService.createPayment(
        req.body,
        req.requestId,
        idempotencyKey
      );

      res.status(201).json(payment);

    } catch (err) {
      next(paymentsService.mapUpstreamError(err));
    }
  }
);

// ── GET /api/v1/payments/:id ─────────────────────────────────────────────────

router.get(
  '/payments/:id',
  authenticate,
  requireRole('PAYMENT_VIEWER', 'PAYMENT_INITIATOR', 'ADMIN'),
  param('id').isUUID(4).withMessage('id must be a valid UUID'),
  validate,

  async (req, res, next) => {
    try {
      const payment = await paymentsService.getPaymentById(req.params.id, req.requestId);
      res.json(payment);
    } catch (err) {
      next(paymentsService.mapUpstreamError(err));
    }
  }
);

// ── GET /api/v1/payments/ref/:reference ──────────────────────────────────────

router.get(
  '/payments/ref/:reference',
  authenticate,
  requireRole('PAYMENT_VIEWER', 'PAYMENT_INITIATOR', 'ADMIN'),
  param('reference')
    .matches(/^PAY-\d{8}-\d{6}-[A-Z0-9]{4}$/)
    .withMessage('Invalid payment reference format'),
  validate,

  async (req, res, next) => {
    try {
      const payment = await paymentsService.getPaymentByReference(
        req.params.reference, req.requestId);
      res.json(payment);
    } catch (err) {
      next(paymentsService.mapUpstreamError(err));
    }
  }
);

// ── GET /api/v1/payments?senderAccountId=...&page=0&size=20 ─────────────────

router.get(
  '/payments',
  authenticate,
  requireRole('PAYMENT_VIEWER', 'PAYMENT_INITIATOR', 'ADMIN'),
  query('senderAccountId').notEmpty().withMessage('senderAccountId query param is required'),
  query('page').optional().isInt({ min: 0 }).withMessage('page must be a non-negative integer'),
  query('size').optional().isInt({ min: 1, max: 100 }).withMessage('size must be 1-100'),
  validate,

  async (req, res, next) => {
    try {
      const { senderAccountId, page = 0, size = 20 } = req.query;
      const payments = await paymentsService.getPayments(
        senderAccountId, parseInt(page), parseInt(size), req.requestId);
      res.json(payments);
    } catch (err) {
      next(paymentsService.mapUpstreamError(err));
    }
  }
);

module.exports = router;
