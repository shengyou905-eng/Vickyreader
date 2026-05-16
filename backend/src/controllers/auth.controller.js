const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { jwtSecret, jwtExpiresIn } = require('../config/env');
const userRepository = require('../repositories/user.repository');
const httpError = require('../utils/httpError');

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
}

function signToken(user) {
  return jwt.sign(
    {
      id: user.id,
      email: user.email,
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

    const ok = await bcrypt.compare(password, userWithPassword.password_hash);
    if (!ok) {
      throw httpError(401, 'Invalid email or password');
    }

    const user = {
      id: userWithPassword.id,
      email: userWithPassword.email,
      created_at: userWithPassword.created_at,
      updated_at: userWithPassword.updated_at,
    };
    const token = signToken(user);

    return res.json({ user, token });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  register,
  login,
};
