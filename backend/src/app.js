const express = require('express');
const cors = require('cors');
const { corsOrigin, nodeEnv } = require('./config/env');
const authRoutes = require('./routes/auth.routes');
const entriesRoutes = require('./routes/entries.routes');
const insightsRoutes = require('./routes/insights.routes');
const mingtaiRoutes = require('./routes/mingtai.routes');
const readingProgressRoutes = require('./routes/readingProgress.routes');
const aiRoutes = require('./routes/ai.routes');
const errorHandler = require('./middleware/errorHandler');

const app = express();

app.use(cors({ origin: corsOrigin === '*' ? true : corsOrigin }));
app.use(express.json({ limit: '2mb' }));

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', env: nodeEnv });
});

app.use('/api/auth', authRoutes);
app.use('/api/entries', entriesRoutes);
app.use('/api/insights', insightsRoutes);
app.use('/api/mingtai', mingtaiRoutes);
app.use('/api/reading-progress', readingProgressRoutes);
app.use('/api/ai', aiRoutes);

app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

app.use(errorHandler);

module.exports = app;
