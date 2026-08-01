'use strict';

/**
 * Request Context Middleware (Plan 05 — Option A)
 * ─────────────────────────────────────────────────────────────
 * แนบ requestId และ child logger ให้ทุก request
 * - ใช้ X-Request-Id จาก header หรือสร้างใหม่ด้วย crypto.randomUUID()
 * - สร้าง child logger ที่ผูก requestId, userId, path อัตโนมัติ
 * - ตั้ง response header X-Request-Id ให้ client ใช้สืบสวนได้
 *
 * ใช้หลัง cors/express.json และก่อ route handlers
 */

const crypto = require('crypto');
const logger = require('../utils/logger');

function requestContext(req, res, next) {
  req.id = req.headers['x-request-id'] || crypto.randomUUID();
  res.setHeader('X-Request-Id', req.id);

  req.log = logger.child({
    requestId: req.id,
    userId: req.userId || req.headers['x-user-id'] || null,
    method: req.method,
    path: req.path,
  });

  next();
}

module.exports = { requestContext, logger };
