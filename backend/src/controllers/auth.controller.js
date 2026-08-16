const bcrypt = require('bcryptjs');
const userRepository = require('../repositories/user.repository');
const appleAuthRepository = require('../repositories/appleAuth.repository');
const { signSessionToken } = require('../services/sessionToken.service');
const {
  decryptRefreshToken,
  revokeRefreshToken,
} = require('../services/appleAuth.service');
const httpError = require('../utils/httpError');
const { deletePublicBookFile } = require('../utils/publicBookStorage');

const AI_CONSENT_VERSION = 1;

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

async function register(req, res, next) {
  try {
    const email = normalizeEmail(req.body.email);
    const password = String(req.body.password || '');

    if (!email || !email.includes('@')) {
      throw httpError(400, 'A valid email is required');
    }

    if (password.length < 6) {
      throw httpError(400, 'Password must be at least 6 characters');
    }

    const existing = await userRepository.findUserByEmail(email);
    if (existing) {
      throw httpError(409, 'Email already registered');
    }

    const passwordHash = await bcrypt.hash(password, 12);
    const user = await userRepository.createUser({ email, passwordHash });
    user.has_password = true;
    user.apple_linked = false;
    const token = signSessionToken(user);

    return res.status(201).json({ user, token });
  } catch (error) {
    return next(error);
  }
}

async function login(req, res, next) {
  try {
    const email = normalizeEmail(req.body.email);
    const password = String(req.body.password || '');

    if (!email || !password) {
      throw httpError(400, 'Email and password are required');
    }

    const userWithPassword = await userRepository.findUserByEmail(email);
    if (!userWithPassword) {
      throw httpError(401, 'Invalid email or password');
    }
    if (userWithPassword.account_status !== 'active') {
      throw httpError(403, '账号已被封禁，请联系支持邮箱申诉');
    }

    const ok =
      Boolean(userWithPassword.password_hash) &&
      (await bcrypt.compare(password, userWithPassword.password_hash));
    if (!ok) {
      throw httpError(401, 'Invalid email or password');
    }

    const user = {
      id: userWithPassword.id,
      email: userWithPassword.email,
      role: userWithPassword.role,
      account_status: userWithPassword.account_status,
      created_at: userWithPassword.created_at,
      updated_at: userWithPassword.updated_at,
      token_version: userWithPassword.token_version,
      has_password: true,
      apple_linked: userWithPassword.apple_linked === true,
    };
    const token = signSessionToken(user);

    return res.json({ user, token });
  } catch (error) {
    return next(error);
  }
}

async function logout(req, res, next) {
  try {
    await userRepository.revokeAllTokens(req.user.id);
    return res.json({ signed_out: true });
  } catch (error) {
    return next(error);
  }
}

async function getAiConsent(req, res) {
  return res.json({
    consented: Number(req.authUser.ai_consent_version || 0) >= AI_CONSENT_VERSION,
    consent_version: Number(req.authUser.ai_consent_version || 0),
    required_version: AI_CONSENT_VERSION,
    consented_at: req.authUser.ai_consent_at || null,
  });
}

async function acceptAiConsent(req, res, next) {
  try {
    if (req.body?.accepted !== true) {
      throw httpError(400, '必须明确同意后才能使用第三方 AI 服务');
    }
    const consent = await userRepository.setAiConsent(
      req.user.id,
      AI_CONSENT_VERSION,
    );
    return res.json({ consented: true, ...consent });
  } catch (error) {
    return next(error);
  }
}

async function revokeAiConsent(req, res, next) {
  try {
    await userRepository.setAiConsent(req.user.id, 0);
    return res.json({ consented: false });
  } catch (error) {
    return next(error);
  }
}

async function deleteAccount(req, res, next) {
  try {
    const password = String(req.body?.password || '');
    const user = await userRepository.findUserByIdWithCredentials(req.user.id);
    if (!user) throw httpError(404, '账号不存在');
    if (user.has_password) {
      if (!password) throw httpError(400, '请输入密码确认注销账号');
      if (!(await bcrypt.compare(password, user.password_hash))) {
        throw httpError(401, '密码不正确');
      }
    } else if (user.apple_linked) {
      if (req.body?.confirm !== true) {
        throw httpError(400, '请确认永久注销 Apple 登录账号');
      }
    } else {
      throw httpError(409, '账号没有可验证的登录方式，请联系支持邮箱');
    }

    const appleIdentity = await appleAuthRepository.findAppleIdentityByUserId(
      req.user.id,
    );
    if (appleIdentity?.refresh_token_encrypted) {
      try {
        await revokeRefreshToken(
          decryptRefreshToken(appleIdentity.refresh_token_encrypted),
        );
      } catch (_) {
        throw httpError(502, '暂时无法撤销 Apple 授权，请稍后重试');
      }
    }
    const deletionData = await userRepository.getAccountDeletionData(req.user.id);
    await userRepository.deleteUser(req.user.id);
    const avatarPath = publicStoragePath(deletionData?.avatar_url);
    if (avatarPath) await deletePublicBookFile(avatarPath);
    return res.json({ deleted: true });
  } catch (error) {
    return next(error);
  }
}

function publicStoragePath(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  try {
    const pathname = new URL(raw, 'https://local.invalid').pathname;
    const normalized = pathname.replace(/^\/+/, '');
    return normalized.startsWith('uploads/profile_avatars/') ? normalized : '';
  } catch (_) {
    return '';
  }
}

module.exports = {
  register,
  login,
  logout,
  getAiConsent,
  acceptAiConsent,
  revokeAiConsent,
  deleteAccount,
  AI_CONSENT_VERSION,
};
