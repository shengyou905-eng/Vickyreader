const express = require('express');
// Deliberately NOT mounted in app.js. No env flag can bypass B2.2 requirements.
function createBookRecapRouter() {
  const router = express.Router();
  router.use((_req, res) => {
    res.set('Cache-Control', 'no-store, private');
    res.status(503).json({
      error: '回望功能尚未开放',
      error_code: 'RECAP_NOT_AVAILABLE',
    });
  });
  return router;
}
module.exports = { createBookRecapRouter };
