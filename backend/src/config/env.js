require('dotenv').config();

const nodeEnv = process.env.NODE_ENV || 'development';

function normalizeMcpTokenTtlDays(value) {
  if (typeof value === 'string' && !value.trim()) return 90;
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 90;
  return Math.min(Math.max(Math.floor(parsed), 1), 365);
}

const required = ['JWT_SECRET', 'DATABASE_URL'];

for (const key of required) {
  if (!process.env[key]) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
}

module.exports = {
  port: Number(process.env.PORT || 3000),
  host: process.env.HOST || (nodeEnv === 'production' ? '127.0.0.1' : '0.0.0.0'),
  nodeEnv,
  jwtSecret: process.env.JWT_SECRET,
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',
  databaseUrl: process.env.DATABASE_URL,
  corsOrigin: process.env.CORS_ORIGIN || '*',
  publicBaseUrl: process.env.PUBLIC_BASE_URL || '',
  supportEmail: process.env.SUPPORT_EMAIL || '2931952407@qq.com',
  authRateLimitSecret: process.env.AUTH_RATE_LIMIT_SECRET || process.env.JWT_SECRET,
  // MCP tokens are separate from app sessions. Keep this secret server-side so
  // the database only ever contains a keyed hash of a generated MCP token.
  mcpTokenHashSecret: process.env.MCP_TOKEN_HASH_SECRET || '',
  mcpTokenTtlDays: normalizeMcpTokenTtlDays(process.env.MCP_TOKEN_TTL_DAYS),
  appleTeamId: process.env.APPLE_TEAM_ID || '',
  appleKeyId: process.env.APPLE_KEY_ID || '',
  appleClientId: process.env.APPLE_CLIENT_ID || '',
  appleAllowedAudiences: String(
    process.env.APPLE_ALLOWED_AUDIENCES || process.env.APPLE_CLIENT_ID || '',
  )
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean),
  applePrivateKey: String(process.env.APPLE_PRIVATE_KEY || '').replace(
    /\\n/g,
    '\n',
  ),
  appleTokenEncryptionKey: process.env.APPLE_TOKEN_ENCRYPTION_KEY || '',
  normalizeMcpTokenTtlDays,
};
