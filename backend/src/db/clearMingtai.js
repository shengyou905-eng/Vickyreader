const fs = require('fs/promises');
const path = require('path');

const { closePool, withTransaction } = require('../config/db');

const shouldClear =
  process.argv.includes('--yes') ||
  String(process.env.CLEAR_MINGTAI || '').toLowerCase() === 'yes';
const auditOnly = process.argv.includes('--audit');

const tables = [
  'community_notifications',
  'community_post_resonances',
  'community_post_comments',
  'community_posts',
  'community_follows',
  'community_book_states',
  'community_readable_assets',
  'community_books',
  'annotation_resonances',
  'annotation_comments',
  'book_resonance',
  'book_discussions',
  'resonances',
  'public_annotations',
  'book_publications',
  'book_chapters',
  'public_books',
  'books',
];

function quoteIdent(identifier) {
  return `"${identifier.replace(/"/g, '""')}"`;
}

async function tableExists(queryFn, tableName) {
  const result = await queryFn('SELECT to_regclass($1) AS table_name', [
    `public.${tableName}`,
  ]);
  return Boolean(result.rows[0]?.table_name);
}

async function countRows(queryFn, tableName) {
  const result = await queryFn(
    `SELECT COUNT(*)::integer AS count FROM ${quoteIdent(tableName)}`,
  );
  return result.rows[0]?.count || 0;
}

async function clearMingtaiTables() {
  return withTransaction(async (queryFn) => {
    const summary = [];

    for (const tableName of tables) {
      if (!(await tableExists(queryFn, tableName))) {
        summary.push({ tableName, before: 0, deleted: 0, skipped: true });
        continue;
      }

      const before = await countRows(queryFn, tableName);
      const deleted = await queryFn(`DELETE FROM ${quoteIdent(tableName)}`);
      summary.push({
        tableName,
        before,
        deleted: deleted.rowCount || 0,
        skipped: false,
      });
    }

    return summary;
  });
}

async function summarizeMingtaiTables() {
  return withTransaction(async (queryFn) => {
    const summary = [];

    for (const tableName of tables) {
      if (!(await tableExists(queryFn, tableName))) {
        summary.push({ tableName, count: 0, skipped: true });
        continue;
      }

      summary.push({
        tableName,
        count: await countRows(queryFn, tableName),
        skipped: false,
      });
    }

    return summary;
  });
}

function assertInside(parentDir, targetDir) {
  const relative = path.relative(parentDir, targetDir);
  if (relative.startsWith('..') || path.isAbsolute(relative)) {
    throw new Error(`Refusing to clear unsafe path: ${targetDir}`);
  }
}

async function clearDirectoryContents(directory) {
  const uploadsRoot = path.resolve(__dirname, '..', '..', 'uploads');
  const target = path.resolve(directory);
  assertInside(uploadsRoot, target);

  await fs.mkdir(target, { recursive: true });
  const entries = await fs.readdir(target, { withFileTypes: true });

  let removed = 0;
  for (const entry of entries) {
    await fs.rm(path.join(target, entry.name), {
      recursive: true,
      force: true,
    });
    removed += 1;
  }

  return { directory: target, removed };
}

async function countDirectoryContents(directory) {
  const uploadsRoot = path.resolve(__dirname, '..', '..', 'uploads');
  const target = path.resolve(directory);
  assertInside(uploadsRoot, target);

  await fs.mkdir(target, { recursive: true });
  const entries = await fs.readdir(target, { withFileTypes: true });
  return { directory: target, count: entries.length };
}

async function clearMingtaiUploads() {
  const backendRoot = path.resolve(__dirname, '..', '..');
  return Promise.all([
    clearDirectoryContents(path.join(backendRoot, 'uploads', 'public_books')),
    clearDirectoryContents(
      path.join(backendRoot, 'uploads', 'public_book_covers'),
    ),
  ]);
}

async function summarizeMingtaiUploads() {
  const backendRoot = path.resolve(__dirname, '..', '..');
  return Promise.all([
    countDirectoryContents(path.join(backendRoot, 'uploads', 'public_books')),
    countDirectoryContents(
      path.join(backendRoot, 'uploads', 'public_book_covers'),
    ),
  ]);
}

function printTableSummary(title, summary) {
  console.log(title);
  for (const item of summary) {
    const suffix = item.skipped ? ' skipped' : '';
    const count = item.count ?? item.before ?? 0;
    const deleted =
      typeof item.deleted === 'number' ? `, deleted=${item.deleted}` : '';
    console.log(`- ${item.tableName}: count=${count}${deleted}${suffix}`);
  }
}

function printUploadSummary(title, summary, countKey) {
  console.log(title);
  for (const item of summary) {
    console.log(`- ${item.directory}: ${countKey}=${item[countKey]}`);
  }
}

async function main() {
  const beforeTables = await summarizeMingtaiTables();
  const beforeUploads = await summarizeMingtaiUploads();
  printTableSummary('MingTai tables before:', beforeTables);
  printUploadSummary('MingTai upload files before:', beforeUploads, 'count');

  if (auditOnly) {
    return;
  }

  if (!shouldClear) {
    console.error(
      'Refusing to clear MingTai data. Re-run with --yes or CLEAR_MINGTAI=yes.',
    );
    process.exitCode = 1;
    return;
  }

  const tableSummary = await clearMingtaiTables();
  const uploadSummary = await clearMingtaiUploads();

  printTableSummary('MingTai tables cleared:', tableSummary);
  printUploadSummary('MingTai upload files cleared:', uploadSummary, 'removed');

  const afterTables = await summarizeMingtaiTables();
  const afterUploads = await summarizeMingtaiUploads();
  printTableSummary('MingTai tables after:', afterTables);
  printUploadSummary('MingTai upload files after:', afterUploads, 'count');
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await closePool();
  });
