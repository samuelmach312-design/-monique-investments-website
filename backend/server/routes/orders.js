const express = require('express');
const router = express.Router();

router.post('/', (req, res) => {
  console.log('Order received:', req.body);
  res.json({ 
    success: true, 
    message: 'Order placed',
    orderId: Date.now()
  });
});

router.get('/', (req, res) => {
  res.json({ success: true, orders: [] });
});

module.exports = router;