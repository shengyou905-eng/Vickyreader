import { mkdir, copyFile } from 'node:fs/promises';
await mkdir('dist/zhidu-sync', { recursive: true });
for (const file of ['main.js', 'manifest.json', 'styles.css', 'README.md', 'LICENSE', 'PRIVACY.md']) {
  await copyFile(file, `dist/zhidu-sync/${file}`);
}
await copyFile('node_modules/zod/LICENSE', 'dist/zhidu-sync/ZOD-LICENSE');
await mkdir('dist/zhidu-sync/examples', { recursive: true });
await copyFile('examples/book.md', 'dist/zhidu-sync/examples/book.md');
console.log('Installable folder: dist/zhidu-sync (no secrets or user state included)');
