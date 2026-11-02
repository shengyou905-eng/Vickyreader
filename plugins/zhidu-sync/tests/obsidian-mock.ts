import { parse } from 'yaml';
export const parseYaml = parse;
export const normalizePath = (path: string) => path;
export const requests: unknown[] = [];
export async function requestUrl(input: unknown) { requests.push(input); throw new Error('unexpected network'); }
export class Notice { constructor(_message: string, _duration?: number) {} }
export class TFile { constructor(public path: string) {} }
export class Plugin {
  data: unknown = null;
  app: any = { secretStorage: { values: new Map<string, string>(),
    getSecret(key: string) { return this.values.get(key) || null; },
    setSecret(key: string, value: string) { this.values.set(key, value); } } };
  handlers = new Map<string, (params: Record<string, string>) => void>();
  commands: unknown[] = [];
  async loadData() { return this.data; }
  async saveData(data: unknown) { this.data = structuredClone(data); }
  registerObsidianProtocolHandler(name: string, callback: (params: Record<string, string>) => void) { this.handlers.set(name, callback); }
  addCommand(command: unknown) { this.commands.push(command); }
  addSettingTab(_tab: unknown) {}
}
export class App {}
export class PluginSettingTab { constructor(_app: unknown, _plugin: unknown) {} }
export class Setting {}
