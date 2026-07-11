function isMeaningfulPublicText(value, { minLength = 10 } = {}) {
  const text = String(value || '').trim();
  const compact = text.replace(/\s+/g, '');
  const characters = Array.from(compact);
  if (characters.length < minLength) return false;

  // Reject content made only from numbers, punctuation, symbols, or emoji.
  if (/^[\p{N}\p{P}\p{S}_]+$/u.test(compact)) return false;

  const normalized = compact.toLowerCase();
  if (/^(测试|測試|test|demo|asdf|qwer|哈哈|呵呵|啊|哈)+[.!！。?？]*$/u.test(normalized)) {
    return false;
  }

  const uniqueCharacters = new Set(characters);
  if (characters.length >= minLength && uniqueCharacters.size <= 2) return false;

  // Four or more repetitions of a tiny fragment are usually placeholder text.
  if (/^(.{1,3})\1{3,}$/u.test(compact)) return false;

  return true;
}

module.exports = {
  isMeaningfulPublicText,
};
