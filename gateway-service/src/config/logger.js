'use strict';

const { createLogger, format, transports } = require('winston');

const isProd = process.env.NODE_ENV === 'production';

/**
 * Structured JSON logger.
 * In production: JSON format for log aggregation (CloudWatch, ELK)
 * In development: colourised human-readable output
 */
const logger = createLogger({
  level: process.env.LOG_LEVEL || 'info',

  format: isProd
    ? format.combine(
        format.timestamp(),
        format.errors({ stack: true }),
        format.json()                    // Machine-parseable in production
      )
    : format.combine(
        format.colorize(),
        format.timestamp({ format: 'HH:mm:ss' }),
        format.printf(({ timestamp, level, message, ...meta }) => {
          const metaStr = Object.keys(meta).length ? ` ${JSON.stringify(meta)}` : '';
          return `${timestamp} [${level}]: ${message}${metaStr}`;
        })
      ),

  defaultMeta: {
    service:     'gateway-service',
    environment: process.env.NODE_ENV || 'local',
  },

  transports: [
    new transports.Console(),
  ],
});

// Morgan stream — pipe HTTP access logs through Winston
const morganStream = {
  write: (message) => {
    // Morgan adds a newline; trim it for clean JSON log lines
    logger.http(message.trim());
  },
};

module.exports = { logger, morganStream };
