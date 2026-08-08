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

  // Don't send password back
  const { password: _, ...userWithoutPassword } = user;
  
  res.json({ 
    success: true, 
    user: userWithoutPassword,
    token: 'fake-jwt-token-' + user.id // Replace with real JWT later
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

router.get('/me', (req, res) => {
  // Mock - in real app you'd verify JWT
  res.json({ success: true, user: null });
});

module.exports = router;