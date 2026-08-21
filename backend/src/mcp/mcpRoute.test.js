process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';
process.env.MCP_TOKEN_HASH_SECRET ||= 'test-mcp-token-hash-secret';

const test = require('node:test');
const assert = require('node:assert/strict');
const mcpRepository = require('../repositories/mcp.repository');
const { createRawToken } = require('../services/mcpToken.service');
const { protocolVersion } = require('./server');
const app = require('../app');

async function readJsonRpcResponse(response) {
  const body = await response.text();
  if (response.headers.get('content-type')?.includes('application/json')) {
    return JSON.parse(body);
  }

  const data = body.match(/^data:\s*(.+)$/m)?.[1];
  assert.ok(data, `Expected JSON or an SSE data frame, received: ${body}`);
  return JSON.parse(data);
}

test('POST /mcp forwards token-derived auth to modern and legacy Streamable HTTP handlers', async () => {
  const originalFind = mcpRepository.findActiveMcpTokenByHash;
  const originalTouch = mcpRepository.touchMcpAccessToken;
  const originalListBooks = mcpRepository.listLibraryBooks;
  const server = app.listen(0, '127.0.0.1');

  try {
    mcpRepository.findActiveMcpTokenByHash = async () => ({
      id: 'mcp-token-id',
      user_id: 'server-owned-user-id',
      account_status: 'active',
      expires_at: '2026-12-01T00:00:00.000Z',
    });
    mcpRepository.touchMcpAccessToken = async () => {};
    mcpRepository.listLibraryBooks = async (userId, args) => ({
      items: [{ book_id: 'book-owned-by-token-user', title: `Owned by ${userId}`, ...args }],
      next_cursor: null,
    });

    await new Promise((resolve, reject) => {
      server.once('listening', resolve);
      server.once('error', reject);
    });
    const { port } = server.address();
    const response = await fetch(`http://127.0.0.1:${port}/mcp`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${createRawToken()}`,
        'content-type': 'application/json',
        'mcp-protocol-version': protocolVersion,
        'mcp-method': 'tools/list',
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 1,
        method: 'tools/list',
        params: {
          _meta: {
            'io.modelcontextprotocol/protocolVersion': protocolVersion,
            'io.modelcontextprotocol/clientInfo': { name: 'zhidu-mcp-route-test', version: '0.1.0' },
            'io.modelcontextprotocol/clientCapabilities': {},
          },
        },
      }),
    });
    const body = await response.json();

    assert.equal(response.status, 200);
    assert.equal(body.result.tools.length, 5);

    const toolResponse = await fetch(`http://127.0.0.1:${port}/mcp`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${createRawToken()}`,
        'content-type': 'application/json',
        'mcp-protocol-version': protocolVersion,
        'mcp-method': 'tools/call',
        'mcp-name': 'list_books',
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 2,
        method: 'tools/call',
        params: {
          name: 'list_books',
          arguments: { limit: 20 },
          _meta: {
            'io.modelcontextprotocol/protocolVersion': protocolVersion,
            'io.modelcontextprotocol/clientInfo': { name: 'zhidu-mcp-route-test', version: '0.1.0' },
            'io.modelcontextprotocol/clientCapabilities': {},
          },
        },
      }),
    });
    const toolBody = await toolResponse.json();

    assert.equal(toolResponse.status, 200);
    assert.match(toolBody.result.content[0].text, /server-owned-user-id/);

    const legacyInitialize = await fetch(`http://127.0.0.1:${port}/mcp`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${createRawToken()}`,
        'content-type': 'application/json',
        accept: 'application/json, text/event-stream',
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 3,
        method: 'initialize',
        params: {
          protocolVersion,
          capabilities: {},
          clientInfo: { name: 'legacy-route-test', version: '1.0.0' },
        },
      }),
    });
    const legacyBody = await readJsonRpcResponse(legacyInitialize);

    assert.equal(legacyInitialize.status, 200);
    assert.equal(legacyBody.result.protocolVersion, '2025-11-25');
    assert.equal(legacyInitialize.headers.get('mcp-session-id'), null);

    const legacyTools = await fetch(`http://127.0.0.1:${port}/mcp`, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${createRawToken()}`,
        'content-type': 'application/json',
        accept: 'application/json, text/event-stream',
        'mcp-protocol-version': legacyBody.result.protocolVersion,
      },
      body: JSON.stringify({
        jsonrpc: '2.0',
        id: 4,
        method: 'tools/list',
        params: {},
      }),
    });
    const legacyToolsBody = await readJsonRpcResponse(legacyTools);

    assert.equal(legacyTools.status, 200);
    assert.equal(legacyToolsBody.result.tools.length, 5);
  } finally {
    mcpRepository.findActiveMcpTokenByHash = originalFind;
    mcpRepository.touchMcpAccessToken = originalTouch;
    mcpRepository.listLibraryBooks = originalListBooks;
    await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
  }
});
