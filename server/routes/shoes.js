const express = require('express');
const router = express.Router();

// Mock data for now - replace with DB later
const shoes = [
  {
    _id: '1',
    name: 'Classic Leather Loafers',
    price: 129.99,
    image: 'https://images.unsplash.com/photo-1582897085656-c636d006a246?w=500',
    description: 'Timeless leather loafers perfect for any occasion'
  },
  {
    _id: '2', 
    name: 'Sport Running Shoes',
    price: 89.99,
    image: 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=500',
    description: 'Lightweight running shoes with superior cushioning'
  },
  {
    _id: '3',
    name: 'Canvas High Tops',
    price: 65.00,
    image: 'https://images.unsplash.com/photo-1525966222134-fcfa99b8ae77?w=500',
    description: 'Classic canvas high tops for casual style'
  },
  {
    _id: '4',
    name: 'Suede Desert Boots',
    price: 149.99,
    image: 'https://images.unsplash.com/photo-1543508282-6319a3e2621f?w=500',
    description: 'Premium suede boots with crepe sole'
  }
];

// GET all shoes
router.get('/', (req, res) => {
  res.json(shoes);
});

// GET single shoe
router.get('/:id', (req, res) => {
  const shoe = shoes.find(s => s._id === req.params.id);
  if (!shoe) return res.status(404).json({ message: 'Shoe not found' });
  res.json(shoe);
});

module.exports = router;