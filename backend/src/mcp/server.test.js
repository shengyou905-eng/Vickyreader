process.env.JWT_SECRET ||= 'test-jwt-secret-that-is-long-enough';
process.env.DATABASE_URL ||= 'postgres://test:test@localhost:5432/test';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createServer, mcpHandler, protocolVersion } = require('./server');

const userA = '00000000-0000-4000-8000-000000000001';
const userB = '00000000-0000-4000-8000-000000000002';

function authInfo(userId = userA) {
  return {
    token: 'zd_mcp_test',
    clientId: 'test-client',
    scopes: ['reading:read'],
    extra: { userId, tokenId: 'token-id' },
  };
}

function textPayload(result) {
  return JSON.parse(result.structuredContent ? JSON.stringify(result.structuredContent) : result.content[0].text);
}

test('registers only the five read-only reading tools', () => {
  const server = createServer({ authInfo: authInfo() });
  assert.deepEqual(Object.keys(server._registeredTools), [
    'list_books',
    'search_books',
    'get_book_traces',
    'search_traces',
    'get_trace',
  ]);
  assert.match(server._registeredTools.search_traces.description, /not semantic or vector search/i);
  assert.match(server._registeredTools.search_traces.description, /Free notes and Xiaou chat history are excluded/i);
});

test('book tools always receive the token-derived user and preserve pagination arguments', async () => {
  const received = [];
  const repository = {
    listLibraryBooks: async (userId, args) => {
      received.push({ userId, args });
      return { items: [{ book_id: 'book-a', title: 'Only mine' }], next_cursor: 'next' };
    },
    listTraces: async () => ({ items: [], next_cursor: null }),
    getTraceById: async () => null,
  };
  const server = createServer({ authInfo: authInfo(userA) }, repository);
  const result = await server._registeredTools.search_books.handler({ query: 'mine', limit: 20 });
  assert.equal(received[0].userId, userA);
  assert.equal(received[0].args.queryText, 'mine');
  assert.equal(received[0].args.limit, 20);
  assert.deepEqual(textPayload(result), { items: [{ book_id: 'book-a', title: 'Only mine' }], next_cursor: 'next' });

  const listResult = await server._registeredTools.list_books.handler({ cursor: 'next', limit: 50 });
  assert.equal(received[1].userId, userA);
  assert.equal(received[1].args.cursor, 'next');
  assert.equal(received[1].args.limit, 50);
  assert.equal(textPayload(listResult).next_cursor, 'next');
});

test('trace list and keyword search remain scoped to the authenticated user', async () => {
  const received = [];
  const repository = {
    listLibraryBooks: async () => ({ items: [], next_cursor: null }),
    listTraces: async (userId, args) => {
      received.push({ userId, args });
      return { items: [{ id: 'trace-a', type: 'thought' }], next_cursor: null };
    },
    getTraceById: async () => null,
  };
  const server = createServer({ authInfo: authInfo(userA) }, repository);
  await server._registeredTools.get_book_traces.handler({
    book_id: 'book-a',
    type: 'thought',
    limit: 20,
  });
  await server._registeredTools.search_traces.handler({
    query: '主体',
    tag: '哲学',
    book_id: 'book-a',
    limit: 50,
  });

  assert.equal(received[0].userId, userA);
  assert.equal(received[0].args.bookId, 'book-a');
  assert.equal(received[0].args.type, 'thought');
  assert.equal(received[1].userId, userA);
  assert.equal(received[1].args.queryText, '主体');
  assert.equal(received[1].args.tag, '哲学');
  assert.equal(received[1].args.bookId, 'book-a');
});

test('a foreign trace id is indistinguishable from a missing trace', async () => {
  let requestedBy;
  const repository = {
    listLibraryBooks: async () => ({ items: [], next_cursor: null }),
    listTraces: async () => ({ items: [], next_cursor: null }),
    getTraceById: async (userId) => {
      requestedBy = userId;
      return null;
    },
  };
  const server = createServer({ authInfo: authInfo(userA) }, repository);
  const result = await server._registeredTools.get_trace.handler({
    trace_id: '00000000-0000-4000-8000-000000000099',
  });
  assert.equal(requestedBy, userA);
  assert.equal(result.isError, true);
  assert.equal(result.content[0].text, 'Reading trace not found.');
  assert.notEqual(userA, userB);
});

test('strict Streamable HTTP accepts a modern per-request envelope and exposes tools', async () => {
  const response = await mcpHandler.fetch(
    new Request('http://localhost/mcp', {
      method: 'POST',
      headers: {
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
            'io.modelcontextprotocol/clientInfo': { name: 'zhidu-mcp-test', version: '0.1.0' },
            'io.modelcontextprotocol/clientCapabilities': {},
          },
        },
      }),
    }),
    { authInfo: authInfo() },
  );
  const body = await response.json();
  assert.equal(response.status, 200);
  assert.equal(body.result.tools.length, 5);
});
