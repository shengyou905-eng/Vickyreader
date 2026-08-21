const { McpServer, createMcpHandler } = require('@modelcontextprotocol/server');
const { toNodeHandler } = require('@modelcontextprotocol/node');
const { z } = require('zod');
const mcpRepository = require('../repositories/mcp.repository');

const protocolVersion = '2026-07-28';

function jsonResult(value) {
  return {
    content: [{ type: 'text', text: JSON.stringify(value, null, 2) }],
    structuredContent: value,
  };
}

function toolError(message) {
  return {
    content: [{ type: 'text', text: message }],
    isError: true,
  };
}

function getUserId(authInfo) {
  const userId = authInfo?.extra?.userId;
  return typeof userId === 'string' && userId ? userId : null;
}

const paginationSchema = {
  cursor: z.string().max(200).optional().describe('Opaque cursor returned by a previous call.'),
  limit: z.number().int().min(1).max(50).optional().describe('Items per page. Defaults to 20; maximum is 50.'),
};

function createServer({ authInfo }, repository = mcpRepository) {
  const userId = getUserId(authInfo);
  const server = new McpServer({ name: 'zhidu-reading-mcp', version: '0.1.0' });

  server.registerTool(
    'list_books',
    {
      title: 'List books',
      description: 'List the authenticated user\'s metadata-only private bookshelf. Imported files, paths, and cover paths are never returned.',
      inputSchema: paginationSchema,
    },
    async (args) => {
      if (!userId) return toolError('MCP authentication is required.');
      return jsonResult(await repository.listLibraryBooks(userId, args));
    },
  );

  server.registerTool(
    'search_books',
    {
      title: 'Search books',
      description: 'Search the authenticated user\'s bookshelf by title or author. This does not search book files or their contents.',
      inputSchema: {
        query: z.string().trim().min(1).max(200).describe('Title or author keywords.'),
        ...paginationSchema,
      },
    },
    async (args) => {
      if (!userId) return toolError('MCP authentication is required.');
      return jsonResult(await repository.listLibraryBooks(userId, {
        ...args,
        queryText: args.query,
      }));
    },
  );

  server.registerTool(
    'get_book_traces',
    {
      title: 'Get book reading traces',
      description: 'Read the authenticated user\'s highlights, thoughts, Xiaou explanations, and Xiaou questions for one private book. Results are paginated.',
      inputSchema: {
        book_id: z.string().trim().min(1).max(200).describe('The book_id returned by list_books or search_books.'),
        type: z.enum(['highlight', 'thought', 'ai_explanation', 'ai_question', 'manual']).optional(),
        ...paginationSchema,
      },
    },
    async (args) => {
      if (!userId) return toolError('MCP authentication is required.');
      return jsonResult(await repository.listTraces(userId, {
        ...args,
        bookId: args.book_id,
      }));
    },
  );

  server.registerTool(
    'search_traces',
    {
      title: 'Search reading traces',
      description: 'Keyword, tag, and text search across the authenticated user\'s reading traces. This is not semantic or vector search. Free notes and Xiaou chat history are excluded.',
      inputSchema: {
        query: z.string().trim().min(1).max(300).describe('Keyword or text to match against excerpt, thought, explanation, or tags.'),
        book_id: z.string().trim().min(1).max(200).optional(),
        tag: z.string().trim().min(1).max(120).optional(),
        type: z.enum(['highlight', 'thought', 'ai_explanation', 'ai_question', 'manual']).optional(),
        ...paginationSchema,
      },
    },
    async (args) => {
      if (!userId) return toolError('MCP authentication is required.');
      return jsonResult(await repository.listTraces(userId, {
        ...args,
        bookId: args.book_id,
        queryText: args.query,
      }));
    },
  );

  server.registerTool(
    'get_trace',
    {
      title: 'Get reading trace',
      description: 'Read a single reading trace owned by the authenticated user. A trace ID from another account is treated as not found.',
      inputSchema: {
        trace_id: z.string().uuid().describe('The trace id returned by a trace list or search tool.'),
      },
    },
    async (args) => {
      if (!userId) return toolError('MCP authentication is required.');
      const trace = await repository.getTraceById(userId, args.trace_id);
      return trace ? jsonResult({ trace }) : toolError('Reading trace not found.');
    },
  );

  return server;
}

const mcpHandler = createMcpHandler(createServer, {
  // Keep the endpoint pinned to the one modern revision we implement.  The
  // 2026-07-28 transport uses server/discover plus a per-request _meta
  // envelope; it intentionally does not negotiate through legacy initialize.
  supportedProtocolVersions: [protocolVersion],
  legacy: 'reject',
  responseMode: 'json',
  onerror(error) {
    console.error('[mcp] request failed', error.message);
  },
});

const mcpNodeHandler = toNodeHandler(mcpHandler, {
  onerror(error) {
    console.error('[mcp] adapter failed', error.message);
  },
});

module.exports = {
  protocolVersion,
  createServer,
  mcpHandler,
  mcpNodeHandler,
};
