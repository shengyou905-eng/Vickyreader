import { bookKey, bookOf, Entity, Page, Plan, Projection, State } from './model';
import { bookMetadata, filename, identity, newNote, region, render, YamlParser } from './markdown';
import { conflict, SyncError } from './errors';
import { sha256 } from './crypto';
export interface VaultPort {
  files(): string[];
  read(path: string): Promise<string>;
  exists(path: string): boolean;
  create(path: string, content: string): Promise<void>;
  process(path: string, transform: (content: string) => string): Promise<void>;
}
export interface Store { get(): State; save(value: State): Promise<void> }
export class SyncEngine {
  private running = false;
  cancelled = false;
  constructor(private store: Store, private vault: VaultPort, private parseYaml: YamlParser,
    private fetchPage: (cursor: string | null) => Promise<Page>) {}
  private check() { if (this.cancelled) throw new SyncError('cancelled', '同步已暂停，已完成的写入和同步位置会保留。'); }
  private async index(state: State): Promise<Map<string, string>> {
    const found = new Map<string, string>();
    const expectedPaths = new Set(Object.values(state.sync.receipts).map(r => r.path));
    for (const path of this.vault.files()) {
      this.check();
      const text = await this.vault.read(path);
      const fm = identity(text, this.parseYaml);
      if (fm?.connection === state.connectionId) {
        if (found.has(fm.bookId)) conflict('发现重复的 Zhidu book ID。请把副本移出测试 Vault 后重试，没有覆盖任何副本。');
        found.set(fm.bookId, path);
      } else if (expectedPaths.has(path)) conflict('已同步笔记的身份字段被修改或损坏，已停止写入。请恢复 frontmatter。');
    }
    return found;
  }
  private projection(state: State, page: Page): { next: Projection; affected: Set<string> } {
    const next = structuredClone(state.sync);
    const affected = new Set<string>();
    if (page.phase === 'snapshot' && !state.sync.cursor) next.snapshotSeen = [];
    if (page.phase === 'snapshot' && next.snapshotSeen === null) throw new SyncError('protocol', '快照分页状态不完整，请重新读取完整数据。');
    if (page.phase === 'incremental' && next.snapshotSeen !== null) throw new SyncError('protocol', '快照尚未完成，服务器提前返回了增量。');
    const seen = new Set(next.snapshotSeen || []);
    for (const c of page.changes) {
      const key = `${c.entity_type}:${c.entity_id}`;
      const old = next.entities[key];
      if (old) affected.add(bookOf(old));
      if (c.operation === 'deleted') delete next.entities[key];
      else if (c.entity) { next.entities[key] = c.entity; affected.add(bookOf(c.entity)); }
      if (page.phase === 'snapshot') seen.add(key);
    }
    if (page.phase === 'snapshot') {
      next.snapshotSeen = [...seen];
      if (!page.has_more) {
        for (const [key, entity] of Object.entries(next.entities)) {
          if (!seen.has(key)) { affected.add(bookOf(entity)); delete next.entities[key]; }
        }
        next.snapshotSeen = null;
      }
    }
    next.cursor = page.next_cursor;
    return { next, affected };
  }
  private async plan(state: State, page: Page): Promise<NonNullable<State['journal']>> {
    const { next, affected } = this.projection(state, page);
    const index = await this.index(state);
    const plans: Plan[] = [];
    const reserved = new Set<string>();
    for (const bookId of affected) {
      const receipt = state.sync.receipts[bookKey(bookId)];
      const existing = index.get(bookId);
      if (receipt && !existing) conflict('一本已同步笔记被删除或移出 Vault。请恢复笔记后重试；插件不会自动重建。');
      if (!receipt && existing) conflict('发现未登记的同 ID 笔记，无法确认哪些内容属于用户，已停止同步。');
      if (!receipt && !Object.values(next.entities).some(e => bookOf(e) === bookId)) continue;
      const managed = await render(bookId, next.entities);
      let path = existing;
      let initial: string | null = null;
      if (path) {
        const current = region(await this.vault.read(path)).text;
        if (await sha256(current) !== receipt.hash) conflict('Zhidu 受管区域被手动修改，已保留原文并暂停同步。请备份修改并恢复上次受管内容后重试。');
      } else {
        const meta = bookMetadata(bookId, next.entities);
        const stem = filename(meta.title);
        path = `Zhidu/Books/${stem}.md`;
        if (this.vault.exists(path) || reserved.has(path)) path = `Zhidu/Books/${stem}-${(await sha256(state.connectionId + bookId)).slice(0, 12)}.md`;
        if (this.vault.exists(path) || reserved.has(path)) conflict('目标文件名已经被占用，未覆盖现有文件。');
        initial = newNote(bookId, state.connectionId!, meta.title, meta.author, managed);
      }
      reserved.add(path);
      plans.push({ bookId, path, beforeHash: receipt?.hash || null, region: managed, initial });
      next.receipts[bookKey(bookId)] = { path, hash: await sha256(managed) };
    }
    return { next, plans, hasMore: page.has_more };
  }
  private async replay(): Promise<boolean> {
    const state = this.store.get();
    const journal = state.journal!;
    const next = structuredClone(journal.next);
    const index = await this.index(state);
    for (const plan of journal.plans) {
      this.check();
      let path = index.get(plan.bookId);
      if (!path) {
        if (!plan.initial) conflict('待更新笔记已不存在。请恢复原文件后重试，游标没有前进。');
        if (this.vault.exists(plan.path)) conflict('待创建位置已有其他文件，未覆盖。');
        await this.vault.create(plan.path, plan.initial);
        path = plan.path;
        index.set(plan.bookId, path);
      } else {
        const observed = await this.vault.read(path);
        const oldRegion = region(observed).text;
        if (oldRegion !== plan.region && (plan.beforeHash === null || await sha256(oldRegion) !== plan.beforeHash)) {
          conflict('待写入笔记出现内容冲突，已停止；同步位置没有前进。');
        }
        await this.vault.process(path, current => {
          const fm = identity(current, this.parseYaml);
          if (fm?.connection !== state.connectionId || fm.bookId !== plan.bookId) conflict('笔记身份在写入时变化，已停止。');
          const area = region(current);
          if (area.text === plan.region) return current;
          if (area.text !== oldRegion) conflict('笔记在同步期间被编辑，已保留你的修改。');
          return current.slice(0, area.start) + plan.region + current.slice(area.end);
        });
      }
      next.receipts[bookKey(plan.bookId)].path = path;
    }
    this.check();
    await this.store.save({ ...state, sync: next, journal: null,
      lastSync: journal.hasMore ? state.lastSync : new Date().toISOString() });
    return journal.hasMore;
  }
  async run(): Promise<void> {
    if (this.running) throw new SyncError('busy', '同步正在进行，请稍候。');
    this.running = true;
    try {
      this.check();
      if (this.store.get().journal && !(await this.replay())) return;
      for (let pages = 0; pages < 2000; pages++) {
        this.check();
        const state = this.store.get();
        const page = await this.fetchPage(state.sync.cursor);
        this.check();
        if (page.has_more && page.next_cursor === state.sync.cursor) throw new SyncError('protocol', '服务器返回了重复分页位置，同步已暂停。');
        const journal = await this.plan(state, page);
        this.check();
        // Persist intent before changing files. Replay accepts either the old
        // region hash or the exact new region, including after a failed ACK.
        await this.store.save({ ...state, journal });
        if (!(await this.replay())) return;
      }
      throw new SyncError('limit', '本次同步量较大，已保留进度。请再次点击同步继续。');
    } finally { this.running = false; }
  }
}
