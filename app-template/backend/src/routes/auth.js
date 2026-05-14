const router = require('express').Router();
const { authRateLimit } = require('../middleware/rateLimit');
const validate = require('../middleware/validate');
const authController = require('../controllers/auth.controller');

const credentialsSchema = {
  email: { type: 'email', required: true },
  password: { type: 'string', required: true, minLength: 8, maxLength: 128 },
};

router.post('/register', authRateLimit, validate(credentialsSchema), authController.register);
router.post('/login', authRateLimit, validate(credentialsSchema), authController.login);

module.exports = router;
