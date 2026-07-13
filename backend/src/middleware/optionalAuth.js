const jwt = require('jsonwebtoken');
const { jwtSecret } = require('../config/env');
const userRepository = require('../repositories/user.repository');

async function optionalAuth(req, res, next) {
  const header = req.headers.authorization || '';
  if (!header) return next();

  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }

  try {
    const payload = jwt.verify(token, jwtSecret);
    const userId = payload.id || payload.userId;
    if (!userId) {
      return res.status(401).json({ error: 'Invalid or expired token' });
    }
    const authUser = await userRepository.findAuthUserById(userId);
    if (!authUser || authUser.account_status !== 'active') {
      return res.status(401).json({ error: '账号不可用或已被封禁' });
    }
    if (Number(payload.tokenVersion || 0) !== Number(authUser.token_version || 0)) {
      return res.status(401).json({ error: '登录状态已失效，请重新登录' });
    }
    req.authUser = authUser;
    req.user = { ...payload, id: userId, role: authUser.role };
    return next();
  } catch (_) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

module.exports = optionalAuth;
