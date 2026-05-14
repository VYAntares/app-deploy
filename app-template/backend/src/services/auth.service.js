const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const pool = require('../db/pool');
const config = require('../config');

const SALT_ROUNDS = 12;

exports.register = async (email, password) => {
  const hash = await bcrypt.hash(password, SALT_ROUNDS);
  const { rows } = await pool.query(
    `INSERT INTO users (email, password_hash) VALUES ($1, $2)
     RETURNING id, email, created_at`,
    [email.toLowerCase(), hash]
  );
  return rows[0];
};

exports.login = async (email, password) => {
  const { rows } = await pool.query(
    'SELECT id, email, password_hash FROM users WHERE email = $1',
    [email.toLowerCase()]
  );
  const user = rows[0];
  if (!user) return null;
  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) return null;
  return { id: user.id, email: user.email };
};

exports.signToken = (user) =>
  jwt.sign({ sub: user.id, email: user.email }, config.jwt.secret, {
    expiresIn: config.jwt.expiresIn,
  });
