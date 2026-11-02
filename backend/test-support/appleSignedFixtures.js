// Synthetic certificates/private keys exist only in the OS temp directory during tests.
// The official SDK still verifies ES256, x5c chain, Apple extension OIDs and identity.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { X509Certificate, randomUUID } = require('node:crypto');
const jwt = require('jsonwebtoken');
const { SignedDataVerifier } = require('@apple/app-store-server-library');
const { BUNDLE_ID, PRODUCTS } = require('../src/config/subscriptions');
const { AppleTransactionVerifier } = require('../src/services/appleTransactionVerifier');

function appleSignedFixtures() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'zhidu-apple-test-ca-'));
  const openssl = process.env.TEST_OPENSSL || (process.platform === 'win32'
    ? 'C:\\Program Files\\Git\\usr\\bin\\openssl.exe' : 'openssl');
  const run = (...args) => execFileSync(openssl, args, { cwd: directory, stdio: 'pipe', windowsHide: true });
  const read = (file) => fs.readFileSync(path.join(directory, file));
  const cleanup = () => {
    const target = path.resolve(directory);
    if (path.dirname(target) !== path.resolve(os.tmpdir())
        || !path.basename(target).startsWith('zhidu-apple-test-ca-')) throw new Error('Unsafe fixture cleanup path');
    fs.rmSync(target, { recursive: true, force: true });
  };
  try {
    run('req', '-x509', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes',
      '-keyout', 'root.key', '-out', 'root.pem', '-days', '2', '-subj', '/CN=Zhidu TEST root',
      '-addext', 'basicConstraints=critical,CA:TRUE');
    fs.writeFileSync(path.join(directory, 'intermediate.ext'),
      'basicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n1.2.840.113635.100.6.2.1=DER:05:00\n');
    fs.writeFileSync(path.join(directory, 'leaf.ext'),
      'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\n1.2.840.113635.100.6.11.1=DER:05:00\n');
    for (const [name, issuer] of [['intermediate', 'root'], ['leaf', 'intermediate']]) {
      run('req', '-new', '-newkey', 'ec', '-pkeyopt', 'ec_paramgen_curve:P-256', '-nodes',
        '-keyout', name + '.key', '-out', name + '.csr', '-subj', '/CN=Zhidu TEST ' + name);
      run('x509', '-req', '-in', name + '.csr', '-CA', issuer + '.pem', '-CAkey', issuer + '.key',
        '-CAcreateserial', '-out', name + '.pem', '-days', '2', '-extfile', name + '.ext');
    }
  } catch (error) { cleanup(); throw error; }
  const roots = [new X509Certificate(read('root.pem')).raw];
  const x5c = ['leaf', 'intermediate', 'root'].map((name) => new X509Certificate(read(name + '.pem')).raw.toString('base64'));
  const key = read('leaf.key');
  const config = (environment = 'Sandbox') => ({ environment, bundleId: BUNDLE_ID, appAppleId: 123456789, roots });
  const verifier = (environment = 'Sandbox') => new AppleTransactionVerifier(config(environment),
    new SignedDataVerifier(roots, false, environment, BUNDLE_ID, 123456789));
  const sign = (value, header = {}) => jwt.sign(value, key, {
    algorithm: 'ES256', noTimestamp: true, header: { x5c, ...header },
  });
  const tx = (changes = {}) => ({ environment: 'Sandbox', bundleId: BUNDLE_ID,
    productId: Object.keys(PRODUCTS)[0], type: 'Auto-Renewable Subscription', inAppOwnershipType: 'PURCHASED',
    originalTransactionId: '100001', transactionId: '100001', appAccountToken: randomUUID(),
    purchaseDate: Date.now() - 300000, expiresDate: Date.now() + 86400000, signedDate: Date.now(), ...changes });
  const renewal = (transaction, changes = {}) => ({ environment: transaction.environment,
    originalTransactionId: transaction.originalTransactionId, productId: transaction.productId,
    appAccountToken: transaction.appAccountToken, autoRenewStatus: 1, signedDate: transaction.signedDate, ...changes });
  const notification = (transaction, rn, changes = {}) => sign({ notificationUUID: randomUUID(),
    notificationType: 'DID_RENEW', version: '2.0', signedDate: Date.now(),
    data: { environment: transaction.environment, bundleId: BUNDLE_ID, appAppleId: 123456789,
      signedTransactionInfo: sign(transaction), signedRenewalInfo: sign(rn) }, ...changes });
  const response = (transaction, rn, status = 1) => ({ environment: transaction.environment,
    bundleId: BUNDLE_ID, appAppleId: 123456789, data: [{ subscriptionGroupIdentifier: '1', lastTransactions: [{
      originalTransactionId: transaction.originalTransactionId, status,
      signedTransactionInfo: sign(transaction), signedRenewalInfo: sign(rn),
    }] }] });
  return { roots, config, verifier, sign, tx, renewal, notification, response, cleanup };
}

module.exports = { appleSignedFixtures };
