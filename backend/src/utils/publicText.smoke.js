const assert = require('assert');
const { isMeaningfulPublicText } = require('./publicText');

assert.strictEqual(isMeaningfulPublicText('1234567890123'), false);
assert.strictEqual(isMeaningfulPublicText('哈哈哈哈哈哈哈哈哈哈'), false);
assert.strictEqual(isMeaningfulPublicText('😀😀😀😀😀😀😀😀😀😀'), false);
assert.strictEqual(isMeaningfulPublicText('这本书让我重新理解了自由与责任。'), true);
assert.strictEqual(isMeaningfulPublicText('她并不是在逃离，而是在学习如何成为自己。'), true);

console.log('Mingtai public text smoke test: ok');
