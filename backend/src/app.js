const express = require('express');
const cors = require('cors');
const { corsOrigin, nodeEnv } = require('./config/env');
const authRoutes = require('./routes/auth.routes');
const entriesRoutes = require('./routes/entries.routes');
const errorHandler = require('./middleware/errorHandler');

const app = express();

app.use(cors({ origin: corsOrigin === '*' ? true : corsOrigin }));
app.use(express.json({ limit: '2mb' }));

app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', env: nodeEnv });
});

app.use('/api/auth', authRoutes);
app.use('/api/entries', entriesRoutes);

app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

app.use(errorHandler);

module.exports = app;
