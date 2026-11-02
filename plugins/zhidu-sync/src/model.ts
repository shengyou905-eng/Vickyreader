import { z } from 'zod';
import { SyncError } from './errors';

const text = z.string().nullable();
const id = z.string().min(1).max(1024);
const date = text;
// PostgreSQL stores chapter_index as TEXT; preserve identifiers without numeric coercion.
const chapterIndex = z.union([z.string(), z.number()]).nullable();
export const bookSchema = z.object({ book_id: id, title: text, author: text, format: text,
  in_library: z.boolean(), added_at: date, last_opened_at: date, created_at: date, updated_at: date });
export const traceSchema = z.object({ id, type: z.enum(['highlight', 'thought', 'ai_explanation', 'ai_question']),
  book_id: id, book_title: text, chapter_index: chapterIndex, chapter_title: text,
  excerpt: text, note: text, explanation: text, tags: z.array(z.string()).nullable(),
  is_important: z.boolean(), created_at: date, updated_at: date });
export const progressSchema = z.object({ id, book_id: id, progress: z.number().min(0).max(1).nullable(),
  chapter_index: chapterIndex, scroll_offset: z.number().nullable(), cfi: text,
  created_at: date, updated_at: date });
export type Book = z.infer<typeof bookSchema>;
export type Trace = z.infer<typeof traceSchema>;
export type Progress = z.infer<typeof progressSchema>;
const live = z.discriminatedUnion('entity_type', [
  z.object({ entity_type: z.literal('book'), entity_id: id, data: bookSchema }),
  z.object({ entity_type: z.literal('trace'), entity_id: id, data: traceSchema }),
  z.object({ entity_type: z.literal('reading_progress'), entity_id: id, data: progressSchema }),
]);
export type Entity = z.infer<typeof live>;
const change = z.object({ entity_type: z.enum(['book', 'trace', 'reading_progress']), entity_id: id,
  operation: z.enum(['created', 'updated', 'deleted']), sequence: z.string().nullable(), version: z.string(), data: z.unknown() });
const pageSchema = z.object({ schema_version: z.literal(1), phase: z.enum(['snapshot', 'incremental']),
  watermark: z.string().regex(/^\d+$/), next_cursor: z.string().min(1).max(2000), has_more: z.boolean(), changes: z.array(change).max(100) });
export type Change = z.infer<typeof change> & { entity?: Entity };
export type Page = Omit<z.infer<typeof pageSchema>, 'changes'> & { changes: Change[] };
export function parsePage(raw: unknown): Page {
  const result = pageSchema.safeParse(raw);
  if (!result.success) throw new SyncError('protocol', '同步数据格式暂不兼容，请更新插件。');
  const keys = new Set<string>();
  const changes = result.data.changes.map(c => {
    const key = `${c.entity_type}:${c.entity_id}`;
    if (keys.has(key)) throw new SyncError('protocol', '同一批数据出现重复 ID，同步已停止，未覆盖笔记。');
    keys.add(key);
    if (c.operation === 'deleted') {
      if (c.data !== null) throw new SyncError('protocol', '删除记录格式异常，同步已停止。');
      return c;
    }
    const entity = live.safeParse(c);
    if (!entity.success || (entity.data.entity_type === 'book' ? entity.data.data.book_id : entity.data.data.id) !== c.entity_id) {
      throw new SyncError('protocol', '阅读记录的 ID 或字段异常，同步已停止。');
    }
    return { ...c, entity: entity.data };
  });
  return { ...result.data, changes };
}
const receipt = z.object({ path: z.string(), hash: z.string() });
export const projectionSchema = z.object({ cursor: z.string().nullable(), entities: z.record(z.string(), live),
  receipts: z.record(z.string(), receipt), snapshotSeen: z.array(z.string()).nullable() });
export type Projection = z.infer<typeof projectionSchema>;
const plan = z.object({ bookId: id, path: z.string(), beforeHash: z.string().nullable(), region: z.string(), initial: z.string().nullable() });
export type Plan = z.infer<typeof plan>;
export const stateSchema = z.object({ schema: z.literal(1), installId: z.uuid(), origin: z.string(),
  connectionId: z.uuid().nullable(), expiresAt: z.string().nullable(), lastSync: z.string().nullable(),
  sync: projectionSchema, journal: z.object({ next: projectionSchema, plans: z.array(plan), hasMore: z.boolean() }).nullable() }).strict();
export type State = z.infer<typeof stateSchema>;
export const emptyProjection = (): Projection => ({ cursor: null, entities: {}, receipts: {}, snapshotSeen: null });
export function initialState(installId: string, origin: string): State {
  return { schema: 1, installId, origin, connectionId: null, expiresAt: null, lastSync: null, sync: emptyProjection(), journal: null };
}
export function bookOf(entity: Entity): string { return entity.data.book_id; }
export function bookKey(id: string): string { return `b:${id}`; }
