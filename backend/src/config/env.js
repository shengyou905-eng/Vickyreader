require('dotenv').config();

const required = ['JWT_SECRET', 'DATABASE_URL'];

for (const key of required) {
  if (!process.env[key]) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
}

module.exports = {
  port: Number(process.env.PORT || 3000),
  nodeEnv: process.env.NODE_ENV || 'development',
  jwtSecret: process.env.JWT_SECRET,
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',
  databaseUrl: process.env.DATABASE_URL,
  corsOrigin: process.env.CORS_ORIGIN || '*',
  publicBaseUrl: process.env.PUBLIC_BASE_URL || '',
  supportEmail: process.env.SUPPORT_EMAIL || '2931952407@qq.com',
};
