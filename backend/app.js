require('dotenv').config(); // Load the variables

const jwt = require('jsonwebtoken');

// Use the variable
const token = jwt.sign({ id: user.id }, process.env.JWT_SECRET, {
  expiresIn: '1h',
});