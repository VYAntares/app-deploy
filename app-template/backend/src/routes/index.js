const router = require('express').Router();

router.use('/health', require('./health'));
router.use('/auth', require('./auth'));
router.use('/users', require('./users'));

module.exports = router;
