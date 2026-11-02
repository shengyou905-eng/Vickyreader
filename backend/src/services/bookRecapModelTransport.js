const { recapError } = require('./bookRecapApiContract');
const { BUDGET } = require('./bookRecapGeneration');

const OUTPUT_BYTES = 131072;
const WIRE_BYTES = 262144;
const failure = code => recapError(502, code);
const tokenCount = n => Number.isSafeInteger(n) && n >= 0 ? n : null;

// The same chat-completion SSE shape as the existing AI path, with bounded
// buffering and usage capture. No SDK retry, redirect or environment lookup.
function createBookRecapModelTransport({ endpoint, apiKey, fetchImpl = globalThis.fetch }) {
  const url = new URL(endpoint);
  if (url.username || url.password || url.search || url.hash ||
      (url.protocol !== 'https:' && !(url.protocol === 'http:' && url.hostname === '127.0.0.1'))) {
    throw Error('Server-configured HTTPS or loopback endpoint required');
  }
  if (typeof apiKey !== 'string' || !apiKey) throw Error('Server credential required');
  return async function run(request, { signal, observe }) {
    const response = await fetchImpl(url, { method: 'POST', redirect: 'error', signal,
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...request, stream: true, stream_options: { include_usage: true },
        thinking: { type: 'disabled' } }) });
    if (!response.ok || !response.headers.get('content-type')?.includes('text/event-stream')) {
      await response.body?.cancel().catch(() => {});
      throw failure('RECAP_UPSTREAM_FAILED');
    }
    if (!response.body) throw failure('RECAP_STREAM_INCOMPLETE');
    const reader = response.body.getReader(), decoder = new TextDecoder('utf-8', { fatal: true });
    let buffer = '', text = '', bytes = 0, wire = 0, stopped = false, doneSeen = false;
    let returnedModel = null, inputTokens = null, outputTokens = null;
    function event(line) {
      if (!line.startsWith('data:')) return;
      const raw = line.slice(5).trim();
      if (doneSeen) throw failure('RECAP_STREAM_INVALID');
      if (raw === '[DONE]') {
        if (!stopped || !text.trim()) throw failure('RECAP_STREAM_INCOMPLETE');
        doneSeen = true;
        return;
      }
      let data;
      try { data = JSON.parse(raw); } catch { throw failure('RECAP_STREAM_INVALID'); }
      if (!data || data.error) throw failure('RECAP_UPSTREAM_FAILED');
      if (data.model != null) {
        if (typeof data.model !== 'string' || !/^[a-zA-Z0-9._:/-]{1,128}$/u.test(data.model) ||
            (returnedModel && returnedModel !== data.model)) throw failure('RECAP_STREAM_INVALID');
        returnedModel = data.model;
      }
      if (data.usage != null) {
        const i = tokenCount(data.usage.prompt_tokens), o = tokenCount(data.usage.completion_tokens);
        if ((inputTokens !== null && i !== inputTokens) || (outputTokens !== null && o !== outputTokens)) {
          throw failure('RECAP_STREAM_INVALID');
        }
        inputTokens = i; outputTokens = o;
        if (o !== null && o > BUDGET.maxOutputTokens) throw failure('RECAP_OUTPUT_BUDGET');
      }
      observe({ returnedModel, inputTokens, outputTokens });
      if (!Array.isArray(data.choices) || data.choices.length > 1) throw failure('RECAP_STREAM_INVALID');
      const choice = data.choices[0];
      if (!choice) return;
      if (choice.index !== 0 || choice.delta?.tool_calls || choice.delta?.function_call ||
          choice.delta?.reasoning_content) throw failure('RECAP_STREAM_INVALID');
      const content = choice.delta?.content;
      if (content != null && typeof content !== 'string') throw failure('RECAP_STREAM_INVALID');
      if (content) {
        if (stopped) throw failure('RECAP_STREAM_INVALID');
        bytes += Buffer.byteLength(content, 'utf8');
        if (bytes > OUTPUT_BYTES) throw failure('RECAP_OUTPUT_BUDGET');
        text += content;
      }
      if (choice.finish_reason != null) {
        if (stopped || choice.finish_reason !== 'stop') throw failure('RECAP_STREAM_INCOMPLETE');
        stopped = true;
      }
    }
    try {
      while (true) {
        signal.throwIfAborted();
        const { value, done } = await reader.read();
        if (value) wire += value.byteLength;
        if (wire > WIRE_BYTES) throw failure('RECAP_OUTPUT_BUDGET');
        buffer += done ? decoder.decode() : decoder.decode(value, { stream: true });
        const lines = buffer.split('\n'); buffer = lines.pop();
        for (const line of lines) event(line.replace(/\r$/u, ''));
        if (done) {
          if (buffer.trim()) event(buffer);
          if (!doneSeen) throw failure('RECAP_STREAM_INCOMPLETE');
          break;
        }
        // DONE is the provider's complete protocol boundary; do not wait for keepalive EOF.
        if (doneSeen) { if (buffer.trim()) throw failure('RECAP_STREAM_INVALID'); break; }
      }
      return { text, completed: true, finishReason: 'stop' };
    } catch (error) {
      if (signal.aborted) throw signal.reason;
      if (error.error_code) throw error;
      throw failure('RECAP_STREAM_INCOMPLETE');
    } finally {
      // Cancellation must not turn a terminal result into an unbounded network wait.
      reader.cancel().catch(() => {});
      reader.releaseLock();
    }
  };
}
module.exports = { createBookRecapModelTransport, OUTPUT_BYTES };
