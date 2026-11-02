import { z } from 'zod';
import { SyncError } from './errors';
import { parsePage } from './model';
export type Transport = (input: { url: string; method: string; headers: Record<string, string>; body?: string }) => Promise<{ status: number; json: unknown }>;
export class Api {
  constructor(readonly origin: string, private transport: Transport) {}
  async call(path: string, token?: string, body?: unknown): Promise<unknown> {
    let timer: ReturnType<typeof setTimeout> | undefined;
    let response: { status: number; json: unknown };
    try {
      response = await Promise.race([
        this.transport({ url: `${this.origin}/api/integrations/obsidian/${path}`,
          method: body === undefined ? 'GET' : 'POST', headers: { 'Content-Type': 'application/json',
            ...(token ? { Authorization: `Bearer ${token}` } : {}) }, ...(body === undefined ? {} : { body: JSON.stringify(body) }) }),
        new Promise<never>((_, reject) => { timer = setTimeout(() => reject(new SyncError('network', '知读服务器暂时未响应，请稍后重试。')), 30000); }),
      ]);
    } catch (error) { throw error instanceof SyncError ? error : new SyncError('network', '暂时无法连接知读服务器，请稍后重试。'); }
    finally { clearTimeout(timer); }
    if (response.status === 401 || response.status === 403) throw new SyncError('auth', '知读授权已失效或被撤销。请断开连接后重新授权。');
    if (response.status === 410) throw new SyncError('cursor', '本次分页已过期。请运行“重新读取完整数据”命令。现有笔记会保留。');
    if (response.status === 400 && path.startsWith('sync')) throw new SyncError('cursor', '同步位置不再有效。请运行“重新读取完整数据”命令。');
    if (response.status === 409 && response.json && typeof response.json === 'object'
        && 'error' in response.json && response.json.error === 'resync_required') {
      throw new SyncError('cursor', '服务器要求重新读取完整数据。现有笔记会保留，请运行对应命令。');
    }
    if (response.status === 429) throw new SyncError('rate', '请求较多，请稍后再同步。当前进度已保留。');
    if (response.status < 200 || response.status >= 300) throw new SyncError('server', '知读暂时无法完成请求，请稍后重试。');
    return response.json;
  }
  async exchange(code: string, verifier: string) {
    const raw = await this.call('token', undefined, { grant_type: 'authorization_code', client_id: 'zhidu-sync',
      redirect_uri: 'obsidian://zhidu-sync', code, code_verifier: verifier });
    const parsed = z.object({ access_token: z.string().regex(/^zd_os_[A-Za-z0-9_-]{43}$/),
      expires_in: z.number().positive(), token_type: z.literal('Bearer'), scope: z.literal('obsidian.sync.read') }).safeParse(raw);
    if (!parsed.success) throw new SyncError('protocol', '授权响应格式异常，请重新连接。');
    return parsed.data;
  }
  async status(token: string) {
    const raw = await this.call('status', token);
    const result = z.object({ connected: z.literal(true), scope: z.literal('obsidian.sync.read'), expires_at: z.string() }).safeParse(raw);
    if (!result.success) throw new SyncError('protocol', '无法确认知读授权状态，请重新连接。');
    return result.data;
  }
  async page(token: string, cursor: string | null) {
    return parsePage(await this.call(`sync?${new URLSearchParams({ limit: '50', ...(cursor ? { cursor } : {}) })}`, token));
  }
  async revoke(token: string) { await this.call('revoke', token, {}); }
}
