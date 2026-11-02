// B2.1 has no live source resolver/invalidation hooks. Flags cannot enable it.
function bookRecapConfig(env = {}) {
  const seconds = (key, fallback, max) => {
    if (env[key] === undefined) return fallback;
    const n = Number(env[key]);
    if (!Number.isSafeInteger(n) || n < 1 || n > max) throw new Error('Invalid ' + key);
    return n;
  };
  return Object.freeze({
    generationEnabled: false,
    readEnabled: false,
    preparedSeconds: seconds('RECAP_TEST_PREPARED_SECONDS', 1800, 86400),
    previewSeconds: seconds('RECAP_TEST_PREVIEW_SECONDS', 86400, 604800),
    operationSeconds: seconds('RECAP_TEST_OPERATION_SECONDS', 120, 600),
    operationMacRetentionSeconds: seconds('RECAP_TEST_MAC_RETENTION_SECONDS', 2592000, 31536000),
    // No cleanup of request IDs/deletion fences is implemented in B2.1.
    onlineRevalidationSeconds: null,
  });
}
module.exports = { bookRecapConfig };
