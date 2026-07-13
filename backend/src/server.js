const app = require('./app');
const { host, port, nodeEnv } = require('./config/env');
const { initSchema } = require('./db/init');

async function start() {
  await initSchema();

  const server = app.listen(port, host, () => {
    console.log(`[${nodeEnv}] Reader backend listening on http://${host}:${port}`);
  });
  server.requestTimeout = 180000;
  server.headersTimeout = 65000;
  server.keepAliveTimeout = 65000;
}

start().catch((error) => {
  console.error('Failed to start backend.');
  console.error(error);
  process.exit(1);
});
