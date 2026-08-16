const crypto = require('crypto');
const { authRateLimitSecret } = require('../config/env');
const appleAuthRepository = require('../repositories/appleAuth.repository');
const { signSessionToken } = require('../services/sessionToken.service');
const appleAuthService = require('../services/appleAuth.service');
const { hashRateLimitKey } = require('../utils/rateLimitHash');
const httpError = require('../utils/httpError');

const CHALLENGE_TTL_MS = 5 * 60 * 1000;

function publicUser(row, overrides = {}) {
  return {
    id: row.id || row.user_id,
    email: row.email,
    role: row.role,
    account_status: row.account_status,
    created_at: row.created_at,
    updated_at: row.updated_at,
    token_version: Number(row.token_version || 0),
    has_password: row.password_hash != null,
    apple_linked: true,
    ...overrides,
  };
}

function createAppleAuthController(dependencies = {}) {
  const repository = dependencies.repository || appleAuthRepository;
  const verifyIdentityToken =
    dependencies.verifyIdentityToken || appleAuthService.verifyIdentityToken;
  const exchangeAuthorizationCode =
    dependencies.exchangeAuthorizationCode ||
    appleAuthService.exchangeAuthorizationCode;
  const revokeRefreshToken =
    dependencies.revokeRefreshToken || appleAuthService.revokeRefreshToken;
  const encryptRefreshToken =
    dependencies.encryptRefreshToken || appleAuthService.encryptRefreshToken;
  const signToken = dependencies.signSessionToken || signSessionToken;

  async function prepare(req, res, next) {
    try {
      const ip = String(req.ip || req.socket?.remoteAddress || 'unknown');
      const allowed = await repository.consumeRateLimit({
        action: 'apple_auth_prepare',
        keyHash: hashRateLimitKey(`ip:${ip}`, authRateLimitSecret),
        windowSeconds: 3600,
        limit: 30,
      });
      if (!allowed) throw httpError(429, '请求过于频繁，请稍后重试');
      const state = crypto.randomBytes(32).toString('base64url');
      await repository.createAppleChallenge({
        stateHash: appleAuthService.sha256(state),
        expiresAt: new Date(Date.now() + CHALLENGE_TTL_MS),
      });
      return res.json({ state, expires_in: CHALLENGE_TTL_MS / 1000 });
    } catch (error) {
      return next(error);
    }
  }

  async function validateCredential(req) {
    const authorizationCode = String(req.body?.authorizationCode || '').trim();
    const identityToken = String(req.body?.identityToken || '').trim();
    const rawNonce = String(req.body?.rawNonce || '').trim();
    const state = String(req.body?.state || '').trim();
    if (!authorizationCode || !identityToken || !rawNonce || !state) {
      throw httpError(400, 'Apple 登录凭证不完整');
    }
    const stateValid = await repository.consumeAppleChallenge(
      appleAuthService.sha256(state),
    );
    if (!stateValid) throw httpError(401, 'Apple 登录 state 无效或已过期');

    let payload;
    let tokenResponse;
    try {
      payload = await verifyIdentityToken(identityToken, rawNonce);
      tokenResponse = await exchangeAuthorizationCode(authorizationCode);
      if (tokenResponse.id_token) {
        const exchangedPayload = await verifyIdentityToken(
          tokenResponse.id_token,
          rawNonce,
        );
        if (exchangedPayload.sub !== payload.sub) {
          throw new Error('Apple subject mismatch');
        }
      }
    } catch (_) {
      throw httpError(401, 'Apple 登录凭证无效或已过期');
    }
    return { payload, tokenResponse };
  }

  async function login(req, res, next) {
    try {
      const { payload, tokenResponse } = await validateCredential(req);
      const existing = await repository.findAppleIdentityBySub(payload.sub);
      const encryptedRefreshToken = tokenResponse.refresh_token
        ? encryptRefreshToken(tokenResponse.refresh_token)
        : '';
      if (existing) {
        if (existing.account_status !== 'active') {
          throw httpError(403, '账号已被封禁，请联系支持邮箱申诉');
        }
        await repository.bindAppleIdentity({
          userId: existing.user_id,
          appleSub: payload.sub,
          appleEmail: String(payload.email || existing.apple_email || ''),
          encryptedRefreshToken,
        });
        const user = publicUser(existing);
        return res.json({ user, token: signToken(user) });
      }

      const email = String(payload.email || '').trim().toLowerCase();
      if (!email || !email.includes('@')) {
        if (tokenResponse.refresh_token) {
          await revokeRefreshToken(tokenResponse.refresh_token).catch(() => {});
        }
        throw httpError(
          409,
          'Apple 未提供邮箱。请在 Apple ID 设置中停止使用知读后重试。',
          { error_code: 'APPLE_EMAIL_REQUIRED' },
        );
      }
      const fullName = req.body?.fullName;
      const nickname = [fullName?.givenName, fullName?.familyName]
        .map((item) => String(item || '').trim())
        .filter(Boolean)
        .join(' ')
        .slice(0, 80);
      const created = await repository.createAppleUser({
        email,
        appleSub: payload.sub,
        appleEmail: email,
        encryptedRefreshToken,
        nickname,
      });
      if (created.conflict) {
        if (tokenResponse.refresh_token) {
          await revokeRefreshToken(tokenResponse.refresh_token).catch(() => {});
        }
        throw httpError(
          409,
          '该邮箱已有知读账号。请先使用邮箱登录，再在设置中绑定 Apple。',
          { error_code: 'APPLE_ACCOUNT_LINK_REQUIRED' },
        );
      }
      const user = publicUser(created.user, {
        has_password: false,
        apple_linked: true,
      });
      return res.status(201).json({ user, token: signToken(user) });
    } catch (error) {
      return next(error);
    }
  }

  async function bind(req, res, next) {
    try {
      const { payload, tokenResponse } = await validateCredential(req);
      const encryptedRefreshToken = tokenResponse.refresh_token
        ? encryptRefreshToken(tokenResponse.refresh_token)
        : '';
      const linked = await repository.bindAppleIdentity({
        userId: req.user.id,
        appleSub: payload.sub,
        appleEmail: String(payload.email || ''),
        encryptedRefreshToken,
      });
      if (linked.conflict) {
        if (tokenResponse.refresh_token) {
          await revokeRefreshToken(tokenResponse.refresh_token).catch(() => {});
        }
        throw httpError(409, '该 Apple 账号已绑定其他知读账号', {
          error_code: 'APPLE_BINDING_CONFLICT',
        });
      }
      return res.json({ linked: true });
    } catch (error) {
      return next(error);
    }
  }

  return { prepare, login, bind };
}

module.exports = {
  ...createAppleAuthController(),
  createAppleAuthController,
};
