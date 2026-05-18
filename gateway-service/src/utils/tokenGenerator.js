'use strict';

/**
 * src/utils/tokenGenerator.js
 *
 * LOCAL DEVELOPMENT UTILITY ONLY.
 * Generates signed JWT tokens for manual API testing (Postman, curl).
 *
 * Usage:
 *   node src/utils/tokenGenerator.js
 *   node src/utils/tokenGenerator.js --role ADMIN
 *   node src/utils/tokenGenerator.js --role PAYMENT_VIEWER --expires 24h
 *
 * NEVER use in production. Tokens in production are issued by the
 * Identity Provider (e.g. AWS Cognito, Keycloak).
 */

const jwt  = require('jsonwebtoken');
const path = require('path');
require('dotenv').config({ path: path.resolve(__dirname, '../../.env') });

const VALID_ROLES = [
  'PAYMENT_INITIATOR',
  'PAYMENT_VIEWER',
  'ADMIN',
  'INTERNAL_SERVICE',
];

function generateToken(options = {}) {
  const {
    userId  = 'dev-user-001',
    email   = 'dev@globalpayments.local',
    roles   = ['PAYMENT_INITIATOR'],
    expires = '8h',
  } = options;

  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('JWT_SECRET not set. Copy .env.example to .env first.');
  }

  const payload = {
    sub:   userId,
    email: email,
    roles: roles,
    iss:   process.env.JWT_ISSUER || 'global-payments-auth',
    iat:   Math.floor(Date.now() / 1000),
  };

  return jwt.sign(payload, secret, { expiresIn: expires });
}

// ── CLI entrypoint ──────────────────────────────────────────────────────────

if (require.main === module) {
  const args    = process.argv.slice(2);
  const roleIdx = args.indexOf('--role');
  const expIdx  = args.indexOf('--expires');
  const role    = roleIdx !== -1 ? args[roleIdx + 1] : 'PAYMENT_INITIATOR';
  const expires = expIdx  !== -1 ? args[expIdx  + 1] : '8h';

  if (!VALID_ROLES.includes(role)) {
    console.error(`Invalid role: ${role}`);
    console.error(`Valid roles: ${VALID_ROLES.join(', ')}`);
    process.exit(1);
  }

  try {
    const token = generateToken({ roles: [role], expires });
    const decoded = jwt.decode(token);

    console.log('\n=== Development JWT Token ===');
    console.log(`Role:    ${role}`);
    console.log(`Expires: ${new Date(decoded.exp * 1000).toISOString()}`);
    console.log(`\nAuthorization header:`);
    console.log(`Bearer ${token}`);
    console.log('\n=== Decoded Payload ===');
    console.log(JSON.stringify(decoded, null, 2));
  } catch (err) {
    console.error('Token generation failed:', err.message);
    process.exit(1);
  }
}

module.exports = { generateToken };
