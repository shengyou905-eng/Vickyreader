export class SyncError extends Error {
  constructor(readonly code: string, message: string) { super(message); }
}
export function conflict(message: string): never { throw new SyncError('conflict', message); }
export function userMessage(error: unknown): string {
  return error instanceof SyncError ? error.message : '操作未完成，已保留同步位置和笔记。请检查存储空间与网络后重试。';
}
