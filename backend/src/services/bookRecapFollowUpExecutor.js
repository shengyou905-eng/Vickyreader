const api = require('./bookRecapApiContract');
const { createBookRecapExecutor, principalSchema } = require('./bookRecapExecutor');
const { prepareFollowUp, validateAnswer } = require('./bookRecapFollowUpContract');

// Same bounded, no-retry transport lifecycle. Only the trusted internal workflow
// changes; clients cannot select a workflow, resolver or result validator.
function createBookRecapFollowUpExecutor(options) {
  const { storage, authorize } = options;
  const executor = createBookRecapExecutor({ ...options,
    storage: { begin: storage.beginFollowUp, dispatch: storage.dispatchFollowUp,
      complete: storage.completeFollowUp, fail: storage.failFollowUp, cancel: storage.cancel },
    workflow: { requestSchema: api.followUp, prepare: prepareFollowUp, validate: validateAnswer },
  });
  async function list(value, id) {
    const principal = principalSchema.parse(value);
    return storage.getFollowUps(principal.userId, api.uuid.parse(id),
      (tx, userId) => authorize(tx, userId, principal));
  }
  return { ask: executor.generate, cancel: executor.cancel, list };
}
module.exports = { createBookRecapFollowUpExecutor };
