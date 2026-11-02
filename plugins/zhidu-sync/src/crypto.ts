export function randomId(): string { return crypto.randomUUID(); }
export function randomSecret(): string {
  return base64url(crypto.getRandomValues(new Uint8Array(32)));
}
function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
}
export async function sha256(value: string): Promise<string> {
  return base64url(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))));
}
