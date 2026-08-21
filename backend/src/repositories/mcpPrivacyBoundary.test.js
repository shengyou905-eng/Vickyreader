const fs = require('fs');
const path = require('path');
const test = require('node:test');
const assert = require('node:assert/strict');

const repositorySource = fs.readFileSync(path.join(__dirname, 'mcp.repository.js'), 'utf8');

test('MCP data queries are user-scoped and never read free notes or Xiaou conversations', () => {
  assert.match(repositorySource, /FROM user_library_books b[\s\S]*?WHERE b\.user_id = \$1/);
  assert.match(repositorySource, /FROM user_entries[\s\S]*?WHERE user_id = \$1/);
  assert.match(repositorySource, /WHERE id = \$1 AND user_id = \$2/);
  assert.doesNotMatch(repositorySource, /free_notes|xiaou_conversations|ai_conversations/i);
});

test('MCP trace output intentionally excludes raw local metadata and account fields', () => {
  const traceProjection = repositorySource.match(/function toTrace\(row\) \{([\s\S]*?)\n\}/)?.[1] || '';
  assert.doesNotMatch(traceProjection, /metadata_json|user_id|email|file_path|cover_path/i);
});
