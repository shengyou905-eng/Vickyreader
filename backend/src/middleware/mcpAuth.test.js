process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';
process.env.MCP_TOKEN_HASH_SECRET ||= 'test-mcp-token-hash-secret';

const test = require('node:test');
const assert = require('node:assert/strict');
const mcpRepository = require('../repositories/mcp.repository');
const { createRawToken } = require('../services/mcpToken.service');
const { mcpAuth } = require('./mcpAuth');

function responseRecorder() {
  return {
    statusCode: 200,
    payload: null,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this.payload = payload;
      return this;
    },
  };
}

async function authenticate(authorization) {
  const req = { headers: { authorization } };
  const res = responseRecorder();
  let forwarded;
  let failure;
  await mcpAuth(req, res, (value) => {
    if (value) failure = value;
    else forwarded = true;
  });
  return { req, res, forwarded, failure };
}

test('rejects missing, invalid, and revoked MCP tokens', async () => {
  const originalFind = mcpRepository.findActiveMcpTokenByHash;
  try {
    mcpRepository.findActiveMcpTokenByHash = async () => null;
    assert.equal((await authenticate('')).res.statusCode, 401);
    assert.equal((await authenticate('Bearer not-an-mcp-token')).res.statusCode, 401);
    const token = createRawToken();
    assert.equal((await authenticate(`Bearer ${token}`)).res.statusCode, 401);
  } finally {
    mcpRepository.findActiveMcpTokenByHash = originalFind;
  }
});

test('maps an active custom token to its server-owned user only', async () => {
  const originalFind = mcpRepository.findActiveMcpTokenByHash;
  const originalTouch = mcpRepository.touchMcpAccessToken;
  try {
    mcpRepository.findActiveMcpTokenByHash = async () => ({
      id: 'token-id',
      user_id: 'user-a',
      account_status: 'active',
      expires_at: '2026-12-01T00:00:00.000Z',
    });
    mcpRepository.touchMcpAccessToken = async () => {};
    const result = await authenticate(`Bearer ${createRawToken()}`);
    assert.equal(result.forwarded, true);
    assert.equal(result.req.auth.extra.userId, 'user-a');
    assert.equal(result.req.auth.extra.userId, 'user-a');
    assert.equal(result.req.auth.scopes[0], 'reading:read');
  } finally {
    mcpRepository.findActiveMcpTokenByHash = originalFind;
    mcpRepository.touchMcpAccessToken = originalTouch;
  }
});
