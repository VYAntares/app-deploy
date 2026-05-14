const authService = require('../services/auth.service');

exports.register = async (req, res, next) => {
  try {
    const { email, password } = req.body;
    const user = await authService.register(email, password);
    const token = authService.signToken(user);
    res.status(201).json({ token, user: { id: user.id, email: user.email } });
  } catch (err) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'Email already registered' });
    }
    next(err);
  }
};

exports.login = async (req, res, next) => {
  try {
    const { email, password } = req.body;
    const user = await authService.login(email, password);
    if (!user) return res.status(401).json({ error: 'Invalid email or password' });
    const token = authService.signToken(user);
    res.json({ token, user: { id: user.id, email: user.email } });
  } catch (err) {
    next(err);
  }
};
