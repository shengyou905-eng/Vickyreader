process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';
process.env.MCP_TOKEN_HASH_SECRET ||= 'test-mcp-token-hash-secret';

const test = require('node:test');
const assert = require('node:assert/strict');
const mcpRepository = require('../repositories/mcp.repository');
const { createRawToken } = require('../services/mcpToken.service');
const { protocolVersion } = require('./server');
const app = require('../app');

test('POST /mcp forwards token-derived auth to the strict Streamable HTTP handler', async () => {
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
  } finally {
    mcpRepository.findActiveMcpTokenByHash = originalFind;
    mcpRepository.touchMcpAccessToken = originalTouch;
    mcpRepository.listLibraryBooks = originalListBooks;
    await new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
  }
});
