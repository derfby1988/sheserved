'use strict';

const assert = require('node:assert/strict');
const http = require('node:http');
const express = require('express');

const middlewarePath = require.resolve('../middleware');
require.cache[middlewarePath] = {
  id: middlewarePath,
  filename: middlewarePath,
  loaded: true,
  exports: {
    cacheAside: (_key, callback) => callback(),
    TTL: { SESSION: 0 },
    strictRateLimiter: (_req, _res, next) => next(),
    duplicateCheckMiddleware: () => (_req, _res, next) => next(),
  },
};

const { chatApiRoutes } = require('../routes/chat-api');

const callerId = '11111111-2222-3333-4444-555555555555';
const spoofedId = '99999999-8888-7777-6666-555555555555';
const questionId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const message = {
  id: questionId,
  room_id: 'consult_test',
  sender_id: callerId,
  content: 'How are you feeling?',
  type: 'closed_ended_question',
  is_required: true,
  required_status: 'reading',
};
const calls = [];
const supabaseForSync = {
  rpc: async (name, params) => {
    calls.push({ name, params });
    if (name === 'send_closed_ended_question_backend') {
      return { data: { code: 'OK', message_id: questionId }, error: null };
    }
    if (name === 'mark_closed_ended_question_reading_backend') {
      return { data: { code: 'OK', status: 'reading' }, error: null };
    }
    return {
      data: { code: 'OK', selected_index: 1, selected_value: '2' },
      error: null,
    };
  },
  from: () => ({
    select() {
      return this;
    },
    eq() {
      return this;
    },
    maybeSingle: async () => ({ data: message, error: null }),
  }),
};

let identitySource = 'jwt';
const verifyTokenMw = (req, _res, next) => {
  req.user = identitySource ? { id: callerId } : null;
  req.userId = identitySource ? callerId : null;
  req.identitySource = identitySource;
  next();
};

function requestJson(port, path, body) {
  return new Promise((resolve, reject) => {
    const request = http.request(
      {
        host: '127.0.0.1',
        port,
        path,
        method: 'POST',
        headers: { 'content-type': 'application/json' },
      },
      (response) => {
        let text = '';
        response.setEncoding('utf8');
        response.on('data', (chunk) => {
          text += chunk;
        });
        response.on('end', () => {
          resolve({
            status: response.statusCode,
            body: text ? JSON.parse(text) : null,
          });
        });
      },
    );
    request.on('error', reject);
    request.end(JSON.stringify(body));
  });
}

async function main() {
  const app = express();
  app.use(express.json());
  app.use(
    '/api',
    chatApiRoutes({
      pool: null,
      supabaseForSync,
      verifyTokenMw,
    }),
  );
  const server = app.listen(0, '127.0.0.1');
  await new Promise((resolve) => server.once('listening', resolve));
  const port = server.address().port;

  try {
    const sent = await requestJson(port, '/api/chat/closed-ended/send', {
      roomId: 'consult_test',
      content: 'How are you feeling?',
      config: { schema_version: 1, type: 'quantitative', scale_levels: 3 },
      callerId: spoofedId,
    });
    assert.equal(sent.status, 200);
    assert.equal(sent.body.code, 'OK');
    assert.equal(sent.body.message.id, questionId);
    assert.equal(calls[0].name, 'send_closed_ended_question_backend');
    assert.equal(calls[0].params.p_caller_id, callerId);
    assert.notEqual(calls[0].params.p_caller_id, spoofedId);

    const reading = await requestJson(
      port,
      `/api/chat/closed-ended/${questionId}/reading`,
      {},
    );
    assert.equal(reading.status, 200);
    assert.equal(reading.body.code, 'OK');
    assert.equal(calls[1].name, 'mark_closed_ended_question_reading_backend');
    assert.equal(calls[1].params.p_caller_id, callerId);

    const answer = await requestJson(
      port,
      `/api/chat/closed-ended/${questionId}/answer`,
      { selectedIndex: 1, callerId: spoofedId },
    );
    assert.equal(answer.status, 200);
    assert.equal(answer.body.selected_value, '2');
    assert.equal(calls[2].name, 'answer_closed_ended_question_backend');
    assert.equal(calls[2].params.p_caller_id, callerId);
    assert.equal(calls[2].params.p_selected_index, 1);

    identitySource = 'legacy_header';
    const callCount = calls.length;
    const legacy = await requestJson(port, '/api/chat/closed-ended/send', {
      roomId: 'consult_test',
      content: 'How are you feeling?',
      config: { schema_version: 1, type: 'quantitative', scale_levels: 3 },
    });
    assert.equal(legacy.status, 401);
    assert.equal(calls.length, callCount);

    console.log('Passed 4 closed-ended question API tests.');
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
