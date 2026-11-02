class AppleIapError extends Error {
  constructor(code, status = 503) {
    super(code);
    this.code = code;
    this.status = status;
  }
}

module.exports = { AppleIapError };
