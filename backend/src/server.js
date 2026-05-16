const app = require('./app');
const { port, nodeEnv } = require('./config/env');
const { initSchema } = require('./db/init');

async function start() {
  await initSchema();

  app.listen(port, () => {
    console.log(`[${nodeEnv}] Reader backend listening on http://localhost:${port}`);
  });
}

start().catch((error) => {
  console.error('Failed to start backend.');
  console.error(error);
  process.exit(1);
});
