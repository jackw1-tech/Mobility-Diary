import assert from 'node:assert/strict';
import test from 'node:test';
import { sendJson } from '../.tmp-tests/src/services/apiClient.js';
import { authSession } from '../.tmp-tests/src/services/authSession.js';

function installLocalStorage() {
  const store = new Map();
  globalThis.localStorage = {
    getItem(key) {
      return store.has(key) ? store.get(key) : null;
    },
    setItem(key, value) {
      store.set(key, String(value));
    },
    removeItem(key) {
      store.delete(key);
    },
    clear() {
      store.clear();
    },
  };
}

test.beforeEach(() => {
  installLocalStorage();
  authSession.save({
    accessToken: 'expired-access',
    refreshToken: 'valid-refresh',
  });
});

test.afterEach(() => {
  delete globalThis.fetch;
  delete globalThis.localStorage;
});

test('sendJson refreshes an expired web access token and retries the protected request', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({
      url,
      authorization: options.headers?.Authorization,
      body: options.body,
    });

    if (url === '/api/web/users' && options.headers?.Authorization === 'Bearer expired-access') {
      return jsonResponse(401, { detail: 'Unauthorized' });
    }
    if (url === '/api/web/auth/refresh') {
      return jsonResponse(200, {
        user: user(),
        access_token: 'fresh-access',
        refresh_token: 'fresh-refresh',
        token_type: 'Bearer',
        access_expires_at: '2026-07-06T12:00:00Z',
        refresh_expires_at: '2026-08-06T12:00:00Z',
      });
    }
    if (url === '/api/web/users' && options.headers?.Authorization === 'Bearer fresh-access') {
      return jsonResponse(200, [{ id: 7, email: 'staff@example.com' }]);
    }
    return jsonResponse(500, { detail: 'unexpected call' });
  };

  const result = await sendJson('/web/users');

  assert.deepEqual(result, [{ id: 7, email: 'staff@example.com' }]);
  assert.deepEqual(calls.map((call) => call.url), [
    '/api/web/users',
    '/api/web/auth/refresh',
    '/api/web/users',
  ]);
  assert.equal(calls[2].authorization, 'Bearer fresh-access');
  assert.equal(authSession.accessToken(), 'fresh-access');
  assert.equal(authSession.refreshToken(), 'fresh-refresh');
});

test('sendJson shares one refresh across parallel expired-token requests', async () => {
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    calls.push({
      url,
      authorization: options.headers?.Authorization,
    });

    if (url.startsWith('/api/web/users') && options.headers?.Authorization === 'Bearer expired-access') {
      return jsonResponse(401, { detail: 'Unauthorized' });
    }
    if (url === '/api/web/auth/refresh') {
      await new Promise((resolve) => setTimeout(resolve, 5));
      return jsonResponse(200, {
        user: user(),
        access_token: 'fresh-access',
        refresh_token: 'fresh-refresh',
        token_type: 'Bearer',
        access_expires_at: '2026-07-06T12:00:00Z',
        refresh_expires_at: '2026-08-06T12:00:00Z',
      });
    }
    if (url.startsWith('/api/web/users') && options.headers?.Authorization === 'Bearer fresh-access') {
      return jsonResponse(200, []);
    }
    return jsonResponse(500, { detail: 'unexpected call' });
  };

  await Promise.all([
    sendJson('/web/users'),
    sendJson('/web/users?status=PROCESSED'),
  ]);

  assert.equal(calls.filter((call) => call.url === '/api/web/auth/refresh').length, 1);
  assert.equal(authSession.accessToken(), 'fresh-access');
  assert.equal(authSession.refreshToken(), 'fresh-refresh');
});

function jsonResponse(status, payload) {
  return {
    ok: status >= 200 && status < 300,
    status,
    async text() {
      return JSON.stringify(payload);
    },
  };
}

function user() {
  return {
    id: 1,
    email: 'staff@example.com',
    first_name: '',
    last_name: '',
    is_staff: true,
    is_superuser: false,
  };
}
