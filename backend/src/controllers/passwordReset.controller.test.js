process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  createPasswordResetController,
  GENERIC_RESPONSE,
} = require('./passwordReset.controller');

function responseRecorder() {
  return {
    statusCode: 200,
    payload: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(value) {
      this.payload = value;
      return this;
    },
  };
}

function controllerFor({ user = null, rateAllowed = true } = {}) {
  const deliveries = [];
  const resets = [];
  const controller = createPasswordResetController({
    userRepository: { findUserByEmail: async () => user },
    authSecurityRepository: {
      consumeRateLimit: async () => rateAllowed,
      createPasswordReset: async (value) => resets.push(value),
      resetPassword: async () => ({ id: 'user-id' }),
    },
    sendPasswordResetEmail: async (value) => deliveries.push(value),
    hashPassword: async () => 'bcrypt-hash',
  });
  return { controller, deliveries, resets };
}

test('forgot password is enumeration-safe for present and absent email', async () => {
  for (const user of [null, { id: 'user-id' }]) {
    const { controller } = controllerFor({ user });
    const res = responseRecorder();
    await controller.forgotPassword(
      { body: { email: 'Reader@Example.com' }, ip: '127.0.0.1' },
      res,
      assert.fail,
    );
    assert.equal(res.statusCode, 202);
    assert.deepEqual(res.payload, GENERIC_RESPONSE);
  }
});

test('rate-limited forgot password remains enumeration-safe and sends nothing', async () => {
  const { controller, deliveries, resets } = controllerFor({
    user: { id: 'user-id' },
    rateAllowed: false,
  });
  const res = responseRecorder();
  await controller.forgotPassword(
    { body: { email: 'reader@example.com' }, ip: '127.0.0.1' },
    res,
    assert.fail,
  );
  assert.equal(res.statusCode, 202);
  assert.deepEqual(res.payload, GENERIC_RESPONSE);
  assert.equal(deliveries.length, 0);
  assert.equal(resets.length, 0);
});

test('successful reset hashes the password and never persists the raw token', async () => {
  let resetInput;
  const controller = createPasswordResetController({
    userRepository: {},
    authSecurityRepository: {
      resetPassword: async (value) => {
        resetInput = value;
        return { id: 'user-id' };
      },
    },
    hashPassword: async (password) => `bcrypt:${password}`,
  });
  const res = responseRecorder();
  await controller.resetPassword(
    { body: { token: 'one-time-token', password: 'new-password' } },
    res,
    assert.fail,
  );
  assert.deepEqual(res.payload, { reset: true });
  assert.notEqual(resetInput.tokenHash, 'one-time-token');
  assert.equal(resetInput.passwordHash, 'bcrypt:new-password');
});
