const express = require('express');
const routes = require('./routes');
const { globalRateLimit } = require('./middleware/rateLimit');

const app = express();

app.use(express.json());
app.use(globalRateLimit);

app.use('/', routes);

app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(err.status || 500).json({ error: err.message || 'Internal server error' });
});

module.exports = app;
