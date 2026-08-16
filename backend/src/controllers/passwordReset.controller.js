const bcrypt = require('bcryptjs');
const { passwordResetRateLimitSecret } = require('../config/env');
const userRepository = require('../repositories/user.repository');
const authSecurityRepository = require('../repositories/authSecurity.repository');
const passwordResetService = require('../services/passwordReset.service');
const { sendPasswordResetEmail } = require('../services/email.service');
const httpError = require('../utils/httpError');

const GENERIC_RESPONSE = {
  message: '如果该邮箱已注册，我们会发送一封密码重置邮件。',
};

function normalizeEmail(value) {
  return String(value || '').trim().toLowerCase();
}

function createPasswordResetController(dependencies = {}) {
  const users = dependencies.userRepository || userRepository;
  const security = dependencies.authSecurityRepository || authSecurityRepository;
  const sendEmail = dependencies.sendPasswordResetEmail || sendPasswordResetEmail;
  const hashPassword = dependencies.hashPassword || ((password) => bcrypt.hash(password, 12));

  async function forgotPassword(req, res, next) {
    try {
      const email = normalizeEmail(req.body?.email);
      const ip = String(req.ip || req.socket?.remoteAddress || 'unknown');
      const emailKey = passwordResetService.hashRateLimitKey(
        `email:${email}`,
        passwordResetRateLimitSecret,
      );
      const ipKey = passwordResetService.hashRateLimitKey(
        `ip:${ip}`,
        passwordResetRateLimitSecret,
      );
      const [emailAllowed, ipAllowed] = await Promise.all([
        security.consumeRateLimit({
          action: 'password_reset_email',
          keyHash: emailKey,
          windowSeconds: 3600,
          limit: 3,
        }),
        security.consumeRateLimit({
          action: 'password_reset_ip',
          keyHash: ipKey,
          windowSeconds: 3600,
          limit: 10,
        }),
      ]);

      if (emailAllowed && ipAllowed && email.includes('@')) {
        const user = await users.findUserByEmail(email);
        if (user) {
          const token = passwordResetService.createPasswordResetToken();
          await security.createPasswordReset({
            tokenHash: passwordResetService.hashPasswordResetToken(token),
            userId: user.id,
            expiresAt: passwordResetService.passwordResetExpiry(),
          });
          Promise.resolve()
            .then(() => sendEmail({
              email,
              token,
              expiresMinutes: passwordResetService.TOKEN_TTL_MINUTES,
            }))
            .catch((error) => {
              console.error('Password reset email delivery failed:', error.message);
            });
        }
      }

      return res.status(202).json(GENERIC_RESPONSE);
    } catch (error) {
      return next(error);
    }
  }

  async function resetPassword(req, res, next) {
    try {
      const token = String(req.body?.token || '').trim();
      const password = String(req.body?.password || '');
      if (!token || password.length < 6) {
        throw httpError(400, '重置链接无效，或新密码少于 6 位');
      }
      const passwordHash = await hashPassword(password);
      const user = await security.resetPassword({
        tokenHash: passwordResetService.hashPasswordResetToken(token),
        passwordHash,
      });
      if (!user) throw httpError(400, '重置链接无效、已使用或已过期');
      return res.json({ reset: true });
    } catch (error) {
      return next(error);
    }
  }

  return { forgotPassword, resetPassword };
}

module.exports = {
  ...createPasswordResetController(),
  createPasswordResetController,
  GENERIC_RESPONSE,
};
