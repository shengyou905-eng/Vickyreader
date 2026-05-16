const jwt = require('jsonwebtoken');
const { jwtSecret } = require('../config/env');

function auth(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');

  if (scheme !== 'Bearer' || !token) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  try {
    const payload = jwt.verify(token, jwtSecret);
    const userId = payload.id || payload.userId;

    if (!userId) {
      return res.status(401).json({ error: 'Invalid or expired token' });
    }

    req.user = {
      ...payload,
      id: userId,
    };
    return next();
  } catch (_) {
    return res.status(401).json({ error: 'Invalid or expired token' });
  }
}

module.exports = auth;
