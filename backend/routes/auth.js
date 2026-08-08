const express = require('express');
const router = express.Router();

// Temporary in-memory users - replace with DB later
const users = [
  { id: 1, name: 'Test User', email: 'test@test.com', password: '123456' }
];

router.post('/login', (req, res) => {
  const { email, password } = req.body;
  
  if (!email || !password) {
    return res.status(400).json({ 
      success: false, 
      error: 'Email and password required' 
    });
  }

  const user = users.find(u => u.email === email && u.password === password);
  
  if (!user) {
    return res.status(401).json({ 
      success: false, 
      error: 'Invalid email or password' 
    });
  }

  const { password: _, ...userWithoutPassword } = user;
  
  res.json({ 
    success: true, 
    user: userWithoutPassword,
    token: 'fake-jwt-token-' + user.id
  });
});

router.post('/signup', (req, res) => {
  const { name, email, password } = req.body;
  
  if (!name || !email || !password) {
    return res.status(400).json({ 
      success: false, 
      error: 'All fields required' 
    });
  }

  if (users.find(u => u.email === email)) {
    return res.status(400).json({ 
      success: false, 
      error: 'Email already exists' 
    });
  }

  const newUser = { 
    id: users.length + 1, 
    name, 
    email, 
    password 
  };
  
  users.push(newUser);
  
  const { password: _, ...userWithoutPassword } = newUser;
  
  res.status(201).json({ 
    success: true, 
    user: userWithoutPassword,
    token: 'fake-jwt-token-' + newUser.id
  });
});

// Forgot Password - NEW
router.post('/forgot-password', (req, res) => {
  const { email } = req.body;
  
  if (!email) {
    return res.status(400).json({ success: false, error: 'Email required' });
  }

  const user = users.find(u => u.email === email);
  
  if (!user) {
    return res.status(404).json({ success: false, error: 'Email not found' });
  }

  // Reset to 123456
  user.password = '123456';
  
  res.json({ 
    success: true, 
    message: 'Password has been reset to 123456. Please login with new password.',
    resetLink: '/login'
  });
});

router.get('/me', (req, res) => {
  res.json({ success: true, user: null });
});

module.exports = router;