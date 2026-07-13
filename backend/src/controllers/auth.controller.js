const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { jwtSecret, jwtExpiresIn } = require('../config/env');
const userRepository = require('../repositories/user.repository');
const httpError = require('../utils/httpError');
const { deletePublicBookFile } = require('../utils/publicBookStorage');

const AI_CONSENT_VERSION = 1;

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function signToken(user) {
  return jwt.sign(
    {
      id: user.id,
      email: user.email,
      tokenVersion: Number(user.token_version || 0),
    },
    jwtSecret,
    { expiresIn: jwtExpiresIn },
  );
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
    const token = signToken(user);

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

    const ok = await bcrypt.compare(password, userWithPassword.password_hash);
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
    };
    const token = signToken(user);

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
    if (!password) throw httpError(400, '请输入密码确认注销账号');
    const user = await userRepository.findUserByEmail(req.authUser.email);
    if (!user || !(await bcrypt.compare(password, user.password_hash))) {
      throw httpError(401, '密码不正确');
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
