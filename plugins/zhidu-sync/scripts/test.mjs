import { build } from 'esbuild';
import { readdir } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
const tests = (await readdir('tests')).filter(f => f.endsWith('.test.ts'));
await build({ entryPoints: tests.map(f => `tests/${f}`), outdir: '.test', bundle: true, platform: 'node', format: 'cjs', target: 'node22',
  alias: { obsidian: './tests/obsidian-mock.ts' },
  define: { __API_ORIGIN__: JSON.stringify('http://127.0.0.1:3002'), __TEST_BUILD__: 'true' } });
const result = spawnSync(process.execPath, ['--test', ...tests.map(f => `.test/${f.replace('.ts', '.js')}`)], { stdio: 'inherit' });
process.exitCode = result.status ?? 1;
