const jwt = require('jsonwebtoken');
const { jwtSecret, jwtExpiresIn } = require('../config/env');

function signSessionToken(user) {
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

module.exports = { signSessionToken };
