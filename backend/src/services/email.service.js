const nodemailer = require('nodemailer');
const {
  smtpHost,
  smtpPort,
  smtpSecure,
  smtpUser,
  smtpPass,
  smtpFrom,
  passwordResetPublicUrl,
} = require('../config/env');

let transporter;

function getTransporter() {
  if (!smtpHost || !smtpUser || !smtpPass || !smtpFrom) {
    throw new Error('SMTP is not configured');
  }
  transporter ??= nodemailer.createTransport({
    host: smtpHost,
    port: smtpPort,
    secure: smtpSecure,
    auth: { user: smtpUser, pass: smtpPass },
  });
  return transporter;
}

function resetLink(token) {
  const base = String(passwordResetPublicUrl || '').trim();
  if (!base.startsWith('https://')) {
    throw new Error('PASSWORD_RESET_PUBLIC_URL must use HTTPS');
  }
  return `${base.replace(/#.*$/, '')}#token=${encodeURIComponent(token)}`;
}

async function sendPasswordResetEmail({ email, token, expiresMinutes }) {
  const link = resetLink(token);
  await getTransporter().sendMail({
    from: smtpFrom,
    to: email,
    subject: '重置你的知读密码 / Reset your ReadU password',
    text: [
      '你请求重置知读密码。请在 30 分钟内打开以下链接：',
      link,
      '',
      '如果这不是你的操作，请忽略此邮件。',
      '',
      `This link expires in ${expiresMinutes} minutes. If you did not request it, ignore this email.`,
    ].join('\n'),
    html: `<p>你请求重置知读密码。此链接将在 ${expiresMinutes} 分钟后失效。</p>
      <p><a href="${link}">设置新密码</a></p>
      <p>如果这不是你的操作，请忽略此邮件。</p>
      <hr>
      <p>This link expires in ${expiresMinutes} minutes.</p>`,
  });
}

module.exports = { sendPasswordResetEmail, resetLink };
