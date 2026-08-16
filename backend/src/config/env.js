require('dotenv').config();

const nodeEnv = process.env.NODE_ENV || 'development';

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
  passwordResetPublicUrl: process.env.PASSWORD_RESET_PUBLIC_URL || '',
  passwordResetRateLimitSecret:
    process.env.PASSWORD_RESET_RATE_LIMIT_SECRET || process.env.JWT_SECRET,
  smtpHost: process.env.SMTP_HOST || '',
  smtpPort: Number(process.env.SMTP_PORT || 587),
  smtpSecure: String(process.env.SMTP_SECURE || '').toLowerCase() === 'true',
  smtpUser: process.env.SMTP_USER || '',
  smtpPass: process.env.SMTP_PASS || '',
  smtpFrom: process.env.SMTP_FROM || '',
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
};
