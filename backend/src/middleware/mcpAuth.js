const { isMcpToken, hashToken } = require('../services/mcpToken.service');
const mcpRepository = require('../repositories/mcp.repository');

async function mcpAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !isMcpToken(token)) {
    return res.status(401).json({ error: 'Unauthorized MCP token' });
  }

  try {
    const accessToken = await mcpRepository.findActiveMcpTokenByHash(hashToken(token));
    if (!accessToken || accessToken.account_status !== 'active') {
      return res.status(401).json({ error: 'Unauthorized MCP token' });
    }

    // `auth` is the exact shape forwarded by the official Node adapter to
    // createMcpHandler. user_id is only established here, never by the client.
    req.auth = {
      token,
      clientId: `zhidu-mcp:${accessToken.id}`,
      scopes: ['reading:read'],
      expiresAt: Math.floor(new Date(accessToken.expires_at).getTime() / 1000),
      extra: {
        userId: accessToken.user_id,
        tokenId: accessToken.id,
      },
    };
    void mcpRepository.touchMcpAccessToken(accessToken.id).catch(() => {});
    return next();
  } catch (error) {
    return next(error);
  }
}

module.exports = { mcpAuth };
