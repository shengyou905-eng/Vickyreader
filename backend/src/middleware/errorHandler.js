function errorHandler(error, _req, res, _next) {
  console.error(error);

  if (error.statusCode) {
    return res.status(error.statusCode).json({
      error: error.message,
      ...(error.missing_fields ? { missing_fields: error.missing_fields } : {}),
      ...(error.details ? { details: error.details } : {}),
    });
  }

  if (error.code === '23505') {
    return res.status(409).json({ error: 'Resource already exists' });
  }

  return res.status(500).json({ error: 'Internal server error' });
}

module.exports = errorHandler;
