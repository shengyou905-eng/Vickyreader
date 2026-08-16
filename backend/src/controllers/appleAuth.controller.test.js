process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createAppleAuthController } = require('./appleAuth.controller');

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

function request({ user, fullName } = {}) {
  return {
    user,
    body: {
      authorizationCode: 'code',
      identityToken: 'identity-token',
      rawNonce: 'raw-nonce',
      state: 'server-state',
      fullName,
    },
  };
}

function dependencies(repository, payload = {}) {
  return {
    repository,
    verifyIdentityToken: async () => ({
      sub: 'apple-sub',
      email: 'private@privaterelay.appleid.com',
      ...payload,
    }),
    exchangeAuthorizationCode: async () => ({ refresh_token: 'refresh' }),
    encryptRefreshToken: () => 'encrypted-refresh',
    revokeRefreshToken: async () => {},
    signSessionToken: (user) => `session-for-${user.id}`,
  };
}

function baseRepository(overrides = {}) {
  return {
    consumeAppleChallenge: async () => true,
    findAppleIdentityBySub: async () => null,
    createAppleUser: async ({ email }) => ({
      user: {
        id: 'new-user',
        email,
        role: 'user',
        account_status: 'active',
        token_version: 0,
      },
    }),
    bindAppleIdentity: async () => ({ linked: true }),
    ...overrides,
  };
}

test('repeated Apple login returns the existing ReadU account', async () => {
  const repository = baseRepository({
    findAppleIdentityBySub: async () => ({
      user_id: 'existing-user',
      email: 'reader@example.com',
      password_hash: null,
      account_status: 'active',
      token_version: 2,
    }),
  });
  const controller = createAppleAuthController(dependencies(repository));
  const res = responseRecorder();
  await controller.login(request(), res, assert.fail);
  assert.equal(res.statusCode, 200);
  assert.equal(res.payload.user.id, 'existing-user');
  assert.equal(res.payload.token, 'session-for-existing-user');
});

test('creates an Apple user with a private relay email and first-use name', async () => {
  let createdInput;
  const repository = baseRepository({
    createAppleUser: async (input) => {
      createdInput = input;
      return {
        user: {
          id: 'new-user',
          email: input.email,
          role: 'user',
          account_status: 'active',
          token_version: 0,
        },
      };
    },
  });
  const controller = createAppleAuthController(dependencies(repository));
  const res = responseRecorder();
  await controller.login(
    request({ fullName: { givenName: 'Xiao', familyName: 'You' } }),
    res,
    assert.fail,
  );
  assert.equal(res.statusCode, 201);
  assert.equal(createdInput.email, 'private@privaterelay.appleid.com');
  assert.equal(createdInput.nickname, 'Xiao You');
});

test('does not silently merge an existing email account', async () => {
  const repository = baseRepository({
    createAppleUser: async () => ({ conflict: 'email' }),
  });
  const controller = createAppleAuthController(dependencies(repository));
  let failure;
  await controller.login(request(), responseRecorder(), (error) => {
    failure = error;
  });
  assert.equal(failure.statusCode, 409);
  assert.equal(failure.error_code, 'APPLE_ACCOUNT_LINK_REQUIRED');
});

test('rejects binding an Apple identity owned by another user', async () => {
  const repository = baseRepository({
    bindAppleIdentity: async () => ({ conflict: 'apple_sub' }),
  });
  const controller = createAppleAuthController(dependencies(repository));
  let failure;
  await controller.bind(
    request({ user: { id: 'current-user' } }),
    responseRecorder(),
    (error) => {
      failure = error;
    },
  );
  assert.equal(failure.statusCode, 409);
  assert.equal(failure.error_code, 'APPLE_BINDING_CONFLICT');
});
