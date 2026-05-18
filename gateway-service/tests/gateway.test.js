'use strict';

const request = require('supertest');
const jwt     = require('jsonwebtoken');

// Set test env variables before requiring app
process.env.NODE_ENV  = 'test';
process.env.JWT_SECRET = 'test-secret-key-32-characters-long!!';
process.env.PAYMENTS_SERVICE_URL = 'http://mock-payments-service';

const app = require('../src/app');

// ── JWT Helper ───────────────────────────────────────────────────────────────

const generateToken = (roles = ['PAYMENT_INITIATOR']) => {
  return jwt.sign(
    { sub: 'user-123', email: 'test@bank.com', roles },
    process.env.JWT_SECRET,
    { expiresIn: '1h', issuer: 'global-payments-auth' }
  );
};

// ── Health Endpoints ─────────────────────────────────────────────────────────

describe('Health Endpoints', () => {
  test('GET /health/liveness returns 200', async () => {
    const res = await request(app).get('/health/liveness');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('UP');
  });

  test('GET /health/readiness returns 200', async () => {
    const res = await request(app).get('/health/readiness');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('UP');
  });
});

// ── Authentication Tests ──────────────────────────────────────────────────────

describe('Authentication Middleware', () => {
  test('POST /api/v1/payments without token returns 401', async () => {
    const res = await request(app)
      .post('/api/v1/payments')
      .send({});
    expect(res.status).toBe(401);
    expect(res.body.code).toBe('UNAUTHORIZED');
  });

  test('POST /api/v1/payments with invalid token returns 401', async () => {
    const res = await request(app)
      .post('/api/v1/payments')
      .set('Authorization', 'Bearer not-a-valid-token')
      .send({});
    expect(res.status).toBe(401);
    expect(res.body.code).toBe('INVALID_TOKEN');
  });

  test('POST /api/v1/payments with viewer role returns 403', async () => {
    const token = generateToken(['PAYMENT_VIEWER']);
    const res = await request(app)
      .post('/api/v1/payments')
      .set('Authorization', `Bearer ${token}`)
      .send({
        senderAccountId:   'GB29NWBK60161331926819',
        receiverAccountId: 'GB82WEST12345698765432',
        receiverBankCode:  'BARCGB22',
        amount:            '100.00',
        currency:          'GBP',
        paymentType:       'DOMESTIC',
      });
    expect(res.status).toBe(403);
    expect(res.body.code).toBe('FORBIDDEN');
  });
});

// ── Input Validation Tests ────────────────────────────────────────────────────

describe('Payment Validation', () => {
  const token = generateToken(['PAYMENT_INITIATOR']);

  test('POST /api/v1/payments with missing required fields returns 400', async () => {
    const res = await request(app)
      .post('/api/v1/payments')
      .set('Authorization', `Bearer ${token}`)
      .send({ currency: 'GBP' });  // Missing many required fields

    expect(res.status).toBe(400);
    expect(res.body.code).toBe('VALIDATION_ERROR');
    expect(res.body.fieldErrors).toBeDefined();
    expect(res.body.fieldErrors.senderAccountId).toBeDefined();
  });

  test('POST /api/v1/payments with negative amount returns 400', async () => {
    const res = await request(app)
      .post('/api/v1/payments')
      .set('Authorization', `Bearer ${token}`)
      .send({
        senderAccountId:   'GB29NWBK60161331926819',
        receiverAccountId: 'GB82WEST12345698765432',
        receiverBankCode:  'BARCGB22',
        amount:            '-50.00',
        currency:          'GBP',
        paymentType:       'DOMESTIC',
      });
    expect(res.status).toBe(400);
    expect(res.body.fieldErrors.amount).toBeDefined();
  });

  test('POST /api/v1/payments with invalid currency returns 400', async () => {
    const res = await request(app)
      .post('/api/v1/payments')
      .set('Authorization', `Bearer ${token}`)
      .send({
        senderAccountId:   'GB29NWBK60161331926819',
        receiverAccountId: 'GB82WEST12345698765432',
        receiverBankCode:  'BARCGB22',
        amount:            '100.00',
        currency:          'XYZ',  // Invalid
        paymentType:       'DOMESTIC',
      });
    expect(res.status).toBe(400);
    expect(res.body.fieldErrors.currency).toBeDefined();
  });

  test('GET /api/v1/payments/:id with non-UUID returns 400', async () => {
    const res = await request(app)
      .get('/api/v1/payments/not-a-uuid')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(400);
    expect(res.body.fieldErrors.id).toBeDefined();
  });
});

// ── 404 Handler ───────────────────────────────────────────────────────────────

describe('404 Handler', () => {
  test('Unknown route returns 404', async () => {
    const res = await request(app).get('/api/v1/unknown-route');
    expect(res.status).toBe(404);
    expect(res.body.code).toBe('NOT_FOUND');
  });
});
