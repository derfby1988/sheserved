'use strict';

/**
 * Global Error Handler + Error Taxonomy (Option B)
 * ─────────────────────────────────────────────────────
 * ปิดช่องโหว่ M2 (error detail รั่วถึง client), M4 (ไม่มี global error handler)
 *
 * AppError: operational error ที่คาดการณ์ได้ → ส่ง code + message + requestId
 * errorHandler: global Express error handler → ไม่เปิดเผย internal detail ใน production
 */

const crypto = require('crypto');

class AppError extends Error {
  constructor(code, message, statusCode = 400, details = null) {
    super(message);
    this.code = code;
    this.statusCode = statusCode;
    this.details = details;
    this.isOperational = true;
  }
}

const SENSITIVE_PATTERNS = [
  /password/i,
  /token/i,
  /secret/i,
  /api[_-]?key/i,
  /authorization/i,
  /phone/i,
  /bearer/i,
];

function redactValue(key, value) {
  if (SENSITIVE_PATTERNS.some((p) => p.test(key))) {
    return '[REDACTED]';
  }
  if (typeof value === 'string' && value.length > 500) {
    return value.substring(0, 200) + '...[truncated]';
  }
  return value;
}

function redactObject(obj) {
  if (!obj || typeof obj !== 'object') return obj;
  const redacted = {};
  for (const [k, v] of Object.entries(obj)) {
    redacted[k] = redactValue(k, v);
  }
  return redacted;
}

function errorHandler(err, req, res, next) {
  const isProd = process.env.NODE_ENV === 'production';
  const requestId = req.id || crypto.randomUUID();

  if (res.headersSent) {
    return next(err);
  }

  const logPayload = {
    requestId,
    method: req.method,
    path: req.path,
    userId: req.userId || req.headers['x-user-id'] || null,
    errorName: err.name || 'Error',
    errorMessage: err.message,
    stack: err.stack,
  };

  if (req.body && Object.keys(req.body).length > 0) {
    logPayload.body = redactObject(req.body);
  }

  if (err.isOperational) {
    console.error('[AppError]', JSON.stringify(logPayload));
    return res.status(err.statusCode).json({
      error: {
        code: err.code,
        message: err.message,
        requestId,
      },
    });
  }

  console.error('[UnhandledError]', JSON.stringify(logPayload));

  res.status(500).json({
    error: {
      code: 'INTERNAL_ERROR',
      message: 'เกิดข้อผิดพลาดภายในระบบ',
      requestId,
      ...(isProd ? {} : { debug: err.message }),
    },
  });
}

const notFoundHandler = (req, res) => {
  res.status(404).json({
    error: {
      code: 'NOT_FOUND',
      message: 'ไม่พบ endpoint ที่ร้องขอ',
      path: req.path,
    },
  });
};

module.exports = {
  AppError,
  errorHandler,
  notFoundHandler,
  redactValue,
  redactObject,
};
