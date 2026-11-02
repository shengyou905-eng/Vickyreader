import { build } from 'esbuild';
const testBuild = process.argv.includes('--test-build');
const origin = new URL(process.env.ZHIDU_API_ORIGIN || (testBuild ? 'http://127.0.0.1:3002' : 'https://api.youxugarden.com'));
if (origin.username || origin.password || origin.search || origin.hash || origin.pathname !== '/') throw new Error('API origin only');
if (origin.protocol !== 'https:' && !(testBuild && origin.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(origin.hostname))) throw new Error('HTTPS required');
if (testBuild && origin.hostname === 'api.youxugarden.com') throw new Error('Test builds must not target production');
await build({ entryPoints: ['src/main.ts'], bundle: true, external: ['obsidian'], format: 'cjs',
  platform: 'browser', target: 'es2022', outfile: 'main.js', sourcemap: false,
  define: { __API_ORIGIN__: JSON.stringify(origin.origin), __TEST_BUILD__: JSON.stringify(testBuild) },
  banner: { js: '/* Zhidu Sync. Bundled dependencies retain their license notices. */' } });
console.log(`Built ${testBuild ? 'TEST' : 'release'} plugin for ${origin.origin}`);
