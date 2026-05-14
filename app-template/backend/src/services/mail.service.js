const nodemailer = require('nodemailer');
const config = require('../config');

let transporter = null;

function getTransporter() {
  if (!transporter) {
    transporter = nodemailer.createTransport({
      host: config.smtp.host,
      port: config.smtp.port,
      secure: config.smtp.port === 465,
      auth: config.smtp.user
        ? { user: config.smtp.user, pass: config.smtp.pass }
        : undefined,
    });
  }
  return transporter;
}

exports.sendMail = async ({ to, subject, html, text }) => {
  if (!config.smtp.host) {
    console.warn('SMTP not configured — email not sent:', subject);
    return;
  }
  await getTransporter().sendMail({
    from: config.contactEmail || config.smtp.user,
    to,
    subject,
    html,
    text,
  });
};
