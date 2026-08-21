const { publicBaseUrl } = require('../config/env');
const mcpRepository = require('../repositories/mcp.repository');
const {
  createRawToken,
  getExpiryDate,
  getTokenPrefix,
  hashToken,
} = require('../services/mcpToken.service');

function mcpEndpoint() {
  const baseUrl = String(publicBaseUrl || '').replace(/\/$/, '');
  return baseUrl ? `${baseUrl}/mcp` : '/mcp';
}

async function getMcpTokenStatus(req, res, next) {
  try {
    const token = await mcpRepository.getActiveMcpTokenForUser(req.user.id);
    return res.json({
      endpoint: mcpEndpoint(),
      access_token: token,
    });
  } catch (error) {
    return next(error);
  }
}

async function generateMcpToken(req, res, next) {
  try {
    const label = String(req.body?.label || 'MCP access').trim().slice(0, 80) || 'MCP access';
    const rawToken = createRawToken();
    const accessToken = await mcpRepository.createMcpAccessToken(req.user.id, {
      tokenHash: hashToken(rawToken),
      tokenPrefix: getTokenPrefix(rawToken),
      label,
      expiresAt: getExpiryDate(),
    });
    // The raw token exists only in this response. Logs and all later reads use
    // the short prefix, never the credential itself.
    return res.status(201).json({
      endpoint: mcpEndpoint(),
      token: rawToken,
      access_token: accessToken,
    });
  } catch (error) {
    return next(error);
  }
}

async function revokeMcpToken(req, res, next) {
  try {
    const revoked = await mcpRepository.revokeMcpTokensForUser(req.user.id);
    return res.json({ revoked });
  } catch (error) {
    return next(error);
  }
}

module.exports = {
  getMcpTokenStatus,
  generateMcpToken,
  revokeMcpToken,
};
