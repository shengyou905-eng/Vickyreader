import { z } from 'zod';
import { Api } from './api';
import { randomSecret, sha256 } from './crypto';
import { SyncError } from './errors';
export interface Secrets { getSecret(key: string): string | null; setSecret(key: string, value: string): void }
const pendingSchema = z.object({ state: z.string(), verifier: z.string(), expires: z.number(), origin: z.string(), exchanging: z.boolean().optional() });
export class Authorization {
  readonly tokenKey: string;
  readonly pendingKey: string;
  constructor(private secrets: Secrets, installId: string, private api: Api, private active: () => boolean = () => true) {
    this.tokenKey = `zhidu-sync-${installId}-token`;
    this.pendingKey = `zhidu-sync-${installId}-pkce`;
  }
  token(): string | null { return this.secrets.getSecret(this.tokenKey) || null; }
  clearToken() { this.secrets.setSecret(this.tokenKey, ''); }
  async begin(): Promise<string> {
    const state = randomSecret();
    const verifier = randomSecret();
    const challenge = await sha256(verifier);
    if (!this.active()) throw new SyncError('cancelled', '插件已停用，请重新连接。');
    this.secrets.setSecret(this.pendingKey, JSON.stringify({ state, verifier, expires: Date.now() + 300000, origin: this.api.origin }));
    const url = new URL(`${this.api.origin}/api/integrations/obsidian/authorize`);
    url.search = new URLSearchParams({ response_type: 'code', client_id: 'zhidu-sync', redirect_uri: 'obsidian://zhidu-sync',
      scope: 'obsidian.sync.read', code_challenge_method: 'S256', code_challenge: challenge, state }).toString();
    return url.toString();
  }
  async complete(params: Record<string, string>) {
    let pending: z.infer<typeof pendingSchema>;
    try { pending = pendingSchema.parse(JSON.parse(this.secrets.getSecret(this.pendingKey) || 'null')); }
    catch { throw new SyncError('state', '此授权不是从当前 Vault 发起的，请回到原 Vault 或重新连接。'); }
    if (pending.state !== params.state || pending.origin !== this.api.origin) throw new SyncError('state', '授权返回校验失败，没有更改连接。');
    if (pending.exchanging) throw new SyncError('state', '此授权码正在处理或已处理，请勿重复返回。');
    this.secrets.setSecret(this.pendingKey, '');
    if (pending.expires < Date.now()) throw new SyncError('state', '本次授权已超时，请重新连接。');
    if (params.error) throw new SyncError('denied', '已取消授权。');
    if (!/^zd_oc_[A-Za-z0-9_-]{43}$/.test(params.code || '')) throw new SyncError('state', '授权返回不完整，请重新连接。');
    const marker = JSON.stringify({ ...pending, exchanging: true });
    this.secrets.setSecret(this.pendingKey, marker);
    let grant: Awaited<ReturnType<Api['exchange']>>;
    try { grant = await this.api.exchange(params.code, pending.verifier); }
    catch (error) {
      if (this.secrets.getSecret(this.pendingKey) === marker) this.secrets.setSecret(this.pendingKey, '');
      throw error;
    }
    // An old instance/request must not overwrite a newer connection after reload.
    if (!this.active() || this.secrets.getSecret(this.pendingKey) !== marker) {
      try { await this.api.revoke(grant.access_token); } catch { /* Orphan grant expires server-side. */ }
      if (this.secrets.getSecret(this.pendingKey) === marker) this.secrets.setSecret(this.pendingKey, '');
      throw new SyncError('cancelled', '此授权已被更新的连接替代，请使用最新授权窗口。');
    }
    this.secrets.setSecret(this.pendingKey, '');
    try { this.secrets.setSecret(this.tokenKey, grant.access_token); }
    catch {
      try { await this.api.revoke(grant.access_token); } catch { /* Server expiry bounds an unreachable grant. */ }
      throw new SyncError('storage', '无法保存到 Obsidian SecretStorage，授权未完成。');
    }
    return new Date(Date.now() + grant.expires_in * 1000).toISOString();
  }
  async disconnect() {
    const token = this.token();
    const pending = this.secrets.getSecret(this.pendingKey);
    if (token) await this.api.revoke(token);
    if (this.token() === token) this.clearToken();
    if (this.secrets.getSecret(this.pendingKey) === pending) this.secrets.setSecret(this.pendingKey, '');
  }
}
