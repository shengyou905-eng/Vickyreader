const express = require('express');
const cors = require('cors');
const path = require('path');
const { corsOrigin, nodeEnv } = require('./config/env');
const authRoutes = require('./routes/auth.routes');
const entriesRoutes = require('./routes/entries.routes');
const insightsRoutes = require('./routes/insights.routes');
const mingtaiRoutes = require('./routes/mingtai.routes');
const readingProgressRoutes = require('./routes/readingProgress.routes');
const aiRoutes = require('./routes/ai.routes');
const freeNotesRoutes = require('./routes/freeNotes.routes');
const xiaouConversationRoutes = require('./routes/xiaouConversation.routes');
const legalRoutes = require('./routes/legal.routes');
const libraryRoutes = require('./routes/library.routes');
const mcpSettingsRoutes = require('./routes/mcpSettings.routes');
const { mcpAuth } = require('./middleware/mcpAuth');
const { mcpNodeHandler } = require('./mcp/server');
const errorHandler = require('./middleware/errorHandler');

const app = express();

app.set('trust proxy', true);
app.use(
  cors({
    origin: corsOrigin === '*' ? true : corsOrigin,
    allowedHeaders: [
      'Authorization',
      'Content-Type',
      'Accept',
      'MCP-Protocol-Version',
      'Mcp-Method',
      'Mcp-Name',
    ],
  }),
);
// Public e-book uploads are disabled; 8 MB still covers compressed avatars
// while limiting oversized JSON request abuse.
app.use(express.json({ limit: '8mb' }));
app.use(
  '/uploads',
  express.static(path.resolve(__dirname, '..', 'uploads'), {
    immutable: true,
    maxAge: '30d',
  }),
);

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', env: nodeEnv });
});

// Legal documents must remain publicly accessible without an account so they
// can be linked from App Store Connect and reviewed before registration.
app.get('/privacy', (_req, res) => res.redirect(302, '/legal/privacy'));
app.use('/legal', legalRoutes);

app.use('/api/auth', authRoutes);
app.use('/api/entries', entriesRoutes);
app.use('/api/insights', insightsRoutes);
app.use('/api/mingtai', mingtaiRoutes);
app.use('/api/reading-progress', readingProgressRoutes);
app.use('/api/ai', aiRoutes);
app.use('/api/free-notes', freeNotesRoutes);
app.use('/api/xiaou', xiaouConversationRoutes);
app.use('/api/library', libraryRoutes);
app.use('/api/mcp', mcpSettingsRoutes);

// MCP v0.1 uses one Streamable HTTP endpoint. The SDK handles modern 2026
// requests and stateless legacy initialize negotiation on this same POST route;
// we intentionally do not expose legacy /sse or /messages routes. Express has
// already parsed JSON, so pass req.body to the official Node adapter.
app.post('/mcp', mcpAuth, (req, res, next) => {
  mcpNodeHandler(req, res, req.body).catch(next);
});

app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

app.use(errorHandler);

module.exports = app;
