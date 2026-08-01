'use strict';

/**
 * Structured Logging + Correlation ID (Plan 05 — Option A)
 * ─────────────────────────────────────────────────────────────
 * ปิดช่องโหว่ G1 (ไม่มี structured logging), G2 (ไม่มี log level),
 * G3 (ไม่มี request ID/correlation ID), G9 (ไม่มี PII/secret redaction)
 *
 * ใช้ pino เป็น logger หลัก:
 * - JSON output ส่งเข้า log aggregator ได้ทันที
 * - Redaction ในตัว — ป้องกัน secret/PII หลุดเข้า log
 * - Log level ควบคุมได้ด้วย LOG_LEVEL env var
 * - Production ใช้ 'info', development ใช้ 'debug'
 *
 * Migration adapter: console.log/error ยังทำงานได้ตามปกติ
 * ทยอยเปลี่ยนไปใช้ logger ทีละ module
 */

const pino = require('pino');

const LOG_LEVEL = process.env.LOG_LEVEL || (process.env.NODE_ENV === 'production' ? 'info' : 'debug');

const logger = pino({
  level: LOG_LEVEL,
  redact: {
    paths: [
      'req.headers.authorization',
      'req.headers["x-user-id"]',
      '*.password',
      '*.token',
      '*.phone',
      '*.refresh_token',
      '*.api_key',
      '*.apiKey',
      '*.secret',
      '*.session_id',
      '*.sessionId',
      '*.access_token',
      '*.accessToken',
    ],
    censor: '[REDACTED]',
  },
  formatters: {
    level: (label) => ({ level: label }),
  },
  timestamp: pino.stdTimeFunctions.isoTime,
});

/**
 * Console adapter — ส่งต่อ console.log/error ไปยัง pino
 * ใช้ชั่วคราวระหว่าง migration ทีละ module
 * ปิดได้โดยตั้ง DISABLE_CONSOLE_ADAPTER=true
 */
if (process.env.DISABLE_CONSOLE_ADAPTER !== 'true') {
  const originalLog = console.log;
  const originalError = console.error;
  const originalWarn = console.warn;

  console.log = function (...args) {
    logger.info(args.map(String).join(' '));
  };
  console.error = function (...args) {
    logger.error(args.map(String).join(' '));
  };
  console.warn = function (...args) {
    logger.warn(args.map(String).join(' '));
  };

  // Preserve originals for rollback if needed
  console._originalLog = originalLog;
  console._originalError = originalError;
  console._originalWarn = originalWarn;
}

module.exports = logger;
