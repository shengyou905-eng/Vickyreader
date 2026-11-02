import { App, Notice, Plugin, PluginSettingTab, Setting, TFile, parseYaml, requestUrl, normalizePath } from 'obsidian';
import { Api } from './api';
import { Authorization } from './auth';
import { randomId } from './crypto';
import { SyncError, userMessage } from './errors';
import { emptyProjection, initialState, State, stateSchema } from './model';
import { Store, SyncEngine, VaultPort } from './sync';
declare const __API_ORIGIN__: string;
declare const __TEST_BUILD__: boolean;

export default class ZhiduSync extends Plugin implements Store {
  state!: State;
  api!: Api;
  auth!: Authorization;
  busy = false;
  message = '';
  connectionValidity: 'unknown' | 'valid' | 'invalid' = 'unknown';
  private tab!: ZhiduSettings;
  private engine?: SyncEngine;
  private disposed = false;
  private ready = false;
  async onload() {
    try {
      const stored: unknown = await this.loadData();
      this.state = stored == null ? initialState(randomId(), __API_ORIGIN__) : stateSchema.parse(stored);
      if (this.state.origin !== __API_ORIGIN__) throw new SyncError('origin', '此安装包指向不同环境。请使用原环境包断开连接，并在独立测试 Vault 安装新包。');
      if (!this.app.secretStorage) throw new SyncError('secret', '需要支持 SecretStorage 的 Obsidian 1.11.4 或更新版本。');
      this.api = new Api(__API_ORIGIN__, async input => {
        const response = await requestUrl({ ...input, throw: false });
        let json: unknown = null;
        try { json = response.json; } catch { /* API errors are mapped without response content. */ }
        return { status: response.status, json };
      });
      if (!stored) await this.save(this.state);
      this.auth = new Authorization(this.app.secretStorage, this.state.installId, this.api, () => !this.disposed);
      this.ready = true;
      this.registerObsidianProtocolHandler('zhidu-sync', params => { void this.action(() => this.callback(params)); });
      this.addCommand({ id: 'sync-now', name: 'Sync now', callback: () => { void this.action(() => this.syncNow()); } });
      this.addCommand({ id: 'restart-snapshot', name: '重新读取完整数据', callback: () => { void this.action(async () => {
        if (this.state.journal) throw new SyncError('journal', '有尚未完成的文件写入，请先解决冲突并再次同步，不能丢弃写入计划。');
        await this.save({ ...this.state, sync: { ...this.state.sync, cursor: null, snapshotSeen: null } });
        await this.syncNow();
      }); } });
    } catch (error) {
      this.message = error instanceof SyncError ? error.message : '本地同步状态无法读取。已停止加载，未重置或覆盖数据，请先备份插件目录。';
      new Notice(this.message, 10000);
    }
    this.tab = new ZhiduSettings(this.app, this);
    this.addSettingTab(this.tab);
    // Intentionally no startup request, timer, background sync or vault listener.
  }
  onunload() { this.disposed = true; if (this.engine) this.engine.cancelled = true; }
  get(): State { return this.state; }
  async save(value: State) {
    if (this.disposed) throw new SyncError('cancelled', '插件已停用，同步已暂停。');
    await this.saveData(value);
    this.state = value;
  }
  available() { return this.ready && !this.busy && !this.disposed; }
  async action(work: () => Promise<void>) {
    if (!this.available()) return;
    this.busy = true; this.message = ''; this.tab?.display();
    try { await work(); }
    catch (error) {
      if (error instanceof SyncError && error.code === 'auth') this.connectionValidity = 'invalid';
      this.message = userMessage(error); new Notice(this.message, 10000);
    }
    finally { this.busy = false; if (!this.disposed) this.tab?.display(); }
  }
  async connect() {
    if (this.auth.token() || this.state.connectionId) throw new SyncError('connected', '请先断开现有连接，再连接账号。已生成笔记不会删除。');
    const url = await this.auth.begin();
    if (this.disposed) return;
    window.open(url, '_blank', 'noopener,noreferrer');
    this.message = '请在浏览器中登录并允许，然后返回发起授权的 Vault。';
  }
  private async callback(params: Record<string, string>) {
    if (this.state.connectionId || this.auth.token()) throw new SyncError('connected', '当前已有连接，未替换账号。');
    const expiresAt = await this.auth.complete(params);
    const issuedToken = this.auth.token();
    try {
      await this.save({ ...this.state, connectionId: randomId(), expiresAt, sync: emptyProjection(), journal: null, lastSync: null });
    } catch (error) {
      if (issuedToken && this.auth.token() === issuedToken) {
        try { await this.api.revoke(issuedToken); } catch { /* Expires independently of local state. */ }
        if (this.auth.token() === issuedToken) this.auth.clearToken();
      }
      throw error;
    }
    this.message = 'Connected to Zhidu';
    this.connectionValidity = 'valid';
    new Notice('Connected to Zhidu');
  }
  async disconnect() {
    await this.auth.disconnect();
    await this.save({ ...this.state, connectionId: null, expiresAt: null, lastSync: null, sync: emptyProjection(), journal: null });
    this.connectionValidity = 'unknown';
    this.message = '已撤销授权并断开连接。已有 Markdown 笔记保留。';
  }
  private vaultPort(): VaultPort {
    const vault = this.app.vault;
    const file = (path: string) => {
      const item = vault.getAbstractFileByPath(path);
      if (!(item instanceof TFile)) throw new SyncError('file', '目标笔记不存在或不是文件，同步已停止。');
      return item;
    };
    return {
      files: () => vault.getMarkdownFiles().map(f => f.path),
      read: path => vault.read(file(path)), exists: path => !!vault.getAbstractFileByPath(path),
      process: async (path, transform) => { await vault.process(file(path), transform); },
      create: async (path, content) => {
        for (const folder of ['Zhidu', 'Zhidu/Books']) {
          if (!vault.getAbstractFileByPath(folder)) {
            try { await vault.createFolder(folder); }
            catch (error) { if (!vault.getAbstractFileByPath(folder)) throw error; }
          }
        }
        await vault.create(normalizePath(path), content);
      },
    };
  }
  async syncNow() {
    const token = this.auth.token();
    if (!token || !this.state.connectionId) throw new SyncError('auth', '请先连接知读。');
    await this.api.status(token);
    this.connectionValidity = 'valid';
    if (this.disposed) return;
    this.engine = new SyncEngine(this, this.vaultPort(), parseYaml, cursor => this.api.page(token, cursor));
    await this.engine.run();
    this.message = '同步完成';
    new Notice('Zhidu Sync：同步完成');
  }
}
class ZhiduSettings extends PluginSettingTab {
  constructor(app: App, private plugin: ZhiduSync) { super(app, plugin); }
  display() {
    const el = this.containerEl;
    el.empty();
    new Setting(el).setName('Zhidu Sync').setHeading();
    if (__TEST_BUILD__) new Setting(el).setName('测试环境').setDesc(__API_ORIGIN__);
    const token = this.plugin.auth?.token();
    const expires = this.plugin.state?.expiresAt;
    const expired = expires && Date.parse(expires) <= Date.now();
    const status = !token ? '未连接' : expired || this.plugin.connectionValidity === 'invalid'
      ? '授权失效或已撤销，请重新连接' : this.plugin.connectionValidity === 'valid' ? 'Connected to Zhidu' : '已保存授权，等待手动同步验证';
    new Setting(el).setName('连接状态').setDesc(this.plugin.busy ? '处理中' : status);
    new Setting(el).setName('Connect to Zhidu').addButton(button => button.setButtonText('Connect to Zhidu').setCta()
      .setDisabled(!this.plugin.available() || !!token || !!this.plugin.state?.connectionId)
      .onClick(() => this.plugin.action(() => this.plugin.connect())));
    new Setting(el).setName('Sync Now').addButton(button => button.setButtonText('Sync Now').setDisabled(!this.plugin.available() || !token)
      .onClick(() => this.plugin.action(() => this.plugin.syncNow())));
    new Setting(el).setName('Disconnect').addButton(button => button.setButtonText('Disconnect')
      .setDisabled(!this.plugin.available() || (!token && !this.plugin.state?.connectionId))
      .onClick(() => this.plugin.action(() => this.plugin.disconnect())));
    new Setting(el).setName('最后同步时间').setDesc(this.plugin.state?.lastSync ? new Date(this.plugin.state.lastSync).toLocaleString() : '尚未同步');
    if (this.plugin.message) el.createEl('p', { text: this.plugin.message, cls: 'zhidu-sync-status' });
  }
}
