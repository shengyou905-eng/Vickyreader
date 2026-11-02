import { Book, Entity, Progress, Trace } from './model';
import { conflict } from './errors';
import { sha256 } from './crypto';
export const START = '<!-- zhidu:managed:start -->';
export const END = '<!-- zhidu:managed:end -->';
export type YamlParser = (text: string) => unknown;
export function identity(content: string, parse: YamlParser): { bookId: string; connection: string } | null {
  const match = /^(?:\uFEFF)?---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/.exec(content);
  if (!match) return null;
  let value: unknown;
  try { value = parse(match[1]); } catch { return null; }
  if (!value || typeof value !== 'object') return null;
  const fm = value as Record<string, unknown>;
  return typeof fm.zhidu_book_id === 'string' && typeof fm.zhidu_connection_id === 'string'
    ? { bookId: fm.zhidu_book_id, connection: fm.zhidu_connection_id } : null;
}
export function region(content: string): { text: string; start: number; end: number } {
  const start = content.indexOf(START);
  const end = content.indexOf(END);
  if (start < 0 || end <= start || content.indexOf(START, start + 1) !== -1 || content.indexOf(END, end + 1) !== -1) {
    conflict('笔记的 Zhidu 受管区域缺失或重复，已停止写入。请先恢复原有标记。');
  }
  return { text: content.slice(start, end + END.length), start, end: end + END.length };
}
function safe(value: string): string {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replace(/[\\`*_{}\[\]()#!|~]/g, '\\$&').replace(/\r\n?/g, '\n');
}
function plain(value: string | null | undefined): string { return value ? safe(value) : '未提供'; }
function line(value: string): string { return safe(value).replaceAll('\n', ' '); }
export function bookMetadata(bookId: string, entities: Record<string, Entity>): { title: string | null; author: string | null } {
  const book = entities[`book:${bookId}`];
  const trace = Object.values(entities).find(e => e.entity_type === 'trace' && e.data.book_id === bookId && e.data.book_title);
  return { title: book?.entity_type === 'book' ? book.data.title : trace?.entity_type === 'trace' ? trace.data.book_title : null,
    author: book?.entity_type === 'book' ? book.data.author : null };
}
export async function render(bookId: string, entities: Record<string, Entity>): Promise<string> {
  const list = Object.values(entities).filter(e => e.data.book_id === bookId);
  const book = list.find(e => e.entity_type === 'book')?.data as Book | undefined;
  const traces = list.filter(e => e.entity_type === 'trace').map(e => e.data as Trace)
    .sort((a, b) => (a.created_at || '').localeCompare(b.created_at || '') || a.id.localeCompare(b.id));
  const progresses = list.filter(e => e.entity_type === 'reading_progress').map(e => e.data as Progress)
    .sort((a, b) => (b.updated_at || '').localeCompare(a.updated_at || '') || a.id.localeCompare(b.id));
  const meta = bookMetadata(bookId, entities);
  const out = [START, '', '## 来自知读', '', `书名：${plain(meta.title)}`, '', `作者：${plain(meta.author)}`];
  if (book) out.push('', `书架：${book.in_library ? '在书架' : '已移出书架，保留阅读痕迹'}`);
  if (!list.length) out.push('', '当前没有可同步的阅读记录。');
  if (progresses.length) {
    const p = progresses[0];
    out.push('', '### 阅读进度', '', p.progress === null ? '未提供' : `${Number((p.progress * 100).toFixed(2))}%`);
    if (p.chapter_index !== null) out.push('', `章节索引：${line(String(p.chapter_index))}`);
    if (p.updated_at) out.push('', `更新：${line(p.updated_at)}`);
  }
  for (const [type, heading] of [['highlight', '划线'], ['thought', '我的想法'], ['ai_explanation', '小U解读'], ['ai_question', '问小U']] as const) {
    const entries = traces.filter(t => t.type === type);
    if (!entries.length) continue;
    out.push('', `### ${heading}`);
    for (const t of entries) {
      out.push('', `#### ${t.chapter_title ? line(t.chapter_title) : t.chapter_index !== null ? `章节索引 ${line(String(t.chapter_index))}` : '阅读片段'}`);
      if (t.excerpt) out.push('', safe(t.excerpt).split('\n').map(s => `> ${s}`).join('\n'));
      if (t.note) out.push('', `${type === 'ai_question' ? '提问' : '想法'}：`, '', safe(t.note));
      if (t.explanation) out.push('', '小U：', '', safe(t.explanation));
      if (t.is_important) out.push('', '重要标记：是');
      if (t.tags?.length) out.push('', `标签：${t.tags.map(line).join('、')}`);
      if (t.created_at) out.push('', `创建：${line(t.created_at)}`);
      if (t.updated_at && t.updated_at !== t.created_at) out.push('', `更新：${line(t.updated_at)}`);
      out.push('', `^zhidu-${(await sha256(t.id)).replace(/_/g, '-').slice(0, 20)}`);
    }
  }
  out.push('', END);
  return out.join('\n');
}
export function newNote(bookId: string, connection: string, title: string | null, author: string | null, managed: string): string {
  return ['---', 'type: zhidu-book', `zhidu_book_id: ${JSON.stringify(bookId)}`,
    `zhidu_connection_id: ${JSON.stringify(connection)}`, `title: ${JSON.stringify(title)}`,
    `author: ${JSON.stringify(author)}`, 'zhidu_sync_schema: 1', '---', '',
    `# ${title ? line(title) : '未命名书籍'}`, '', managed, '', '## 我的笔记', '', ''].join('\n');
}
export function filename(title: string | null): string {
  const value = (title || '未命名书籍').replace(/[<>:"/\\|?*\x00-\x1f]/g, '-').replace(/[. ]+$/g, '').slice(0, 70).trim();
  return !value || /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\.|$)/i.test(value) ? 'Zhidu Book' : value;
}
