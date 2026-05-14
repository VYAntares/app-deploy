const router = require('express').Router();
const requireAuth = require('../middleware/auth');
const validate = require('../middleware/validate');
const usersController = require('../controllers/users.controller');

const updateSchema = {
  name: { type: 'string', maxLength: 100 },
  email: { type: 'email' },
};

router.use(requireAuth);

router.get('/', usersController.list);
router.get('/:id', usersController.get);
router.put('/:id', validate(updateSchema), usersController.update);
router.delete('/:id', usersController.remove);

module.exports = router;
