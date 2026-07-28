'use strict';

/**
 * Circuit Breaker — R14
 * ป้องกัน cascade failure เมื่อ dependency (DB, Redis, external API) ล่ม
 *
 * States: CLOSED → OPEN → HALF_OPEN → CLOSED
 * - CLOSED: ปกติ ให้ผ่าน นับ failures
 * - OPEN: บล็อกทั้งหมด รอ resetTimeout
 * - HALF_OPEN: ยอมรับ request แรก ถ้าสำเร็จ → CLOSED ถ้า fail → OPEN
 */

class CircuitBreaker {
  constructor(options = {}) {
    this.name = options.name || 'default';
    this.maxFailures = options.maxFailures || 5;
    this.resetTimeoutMs = options.resetTimeoutMs || 30000;
    this.failureCount = 0;
    this.state = 'CLOSED';
    this.lastFailureAt = null;
    this.halfOpenTestInFlight = false;
  }

  async execute(fn) {
    if (this.state === 'OPEN') {
      if (Date.now() - this.lastFailureAt >= this.resetTimeoutMs) {
        this.state = 'HALF_OPEN';
        this.halfOpenTestInFlight = false;
        console.log(`[CircuitBreaker:${this.name}] OPEN → HALF_OPEN`);
      } else {
        const retryAfter = Math.ceil((this.resetTimeoutMs - (Date.now() - this.lastFailureAt)) / 1000);
        const err = new Error(`Circuit breaker '${this.name}' is OPEN — retry after ${retryAfter}s`);
        err.code = 'CIRCUIT_OPEN';
        err.retryAfter = retryAfter;
        throw err;
      }
    }

    if (this.state === 'HALF_OPEN' && this.halfOpenTestInFlight) {
      const err = new Error(`Circuit breaker '${this.name}' is HALF_OPEN — test in flight`);
      err.code = 'CIRCUIT_HALF_OPEN';
      throw err;
    }

    if (this.state === 'HALF_OPEN') {
      this.halfOpenTestInFlight = true;
    }

    try {
      const result = await fn();
      this._onSuccess();
      return result;
    } catch (err) {
      this._onFailure();
      throw err;
    }
  }

  _onSuccess() {
    if (this.state === 'HALF_OPEN') {
      console.log(`[CircuitBreaker:${this.name}] HALF_OPEN → CLOSED`);
    }
    this.failureCount = 0;
    this.state = 'CLOSED';
    this.halfOpenTestInFlight = false;
  }

  _onFailure() {
    this.failureCount++;
    this.lastFailureAt = Date.now();
    this.halfOpenTestInFlight = false;

    if (this.state === 'HALF_OPEN') {
      this.state = 'OPEN';
      console.warn(`[CircuitBreaker:${this.name}] HALF_OPEN → OPEN (test failed)`);
    } else if (this.failureCount >= this.maxFailures) {
      this.state = 'OPEN';
      console.warn(`[CircuitBreaker:${this.name}] CLOSED → OPEN (${this.failureCount} failures)`);
    }
  }

  getStatus() {
    return {
      name: this.name,
      state: this.state,
      failureCount: this.failureCount,
      maxFailures: this.maxFailures,
      resetTimeoutMs: this.resetTimeoutMs,
    };
  }
}

module.exports = { CircuitBreaker };
