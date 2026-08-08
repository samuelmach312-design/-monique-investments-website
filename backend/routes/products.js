const express = require('express');
const router = express.Router();
const Product = require('../models/Product');

// Only allow Samuel and Monicah
const ALLOWED_ADMINS = ['Samuel', 'Monicah', 'samuel', 'monicah', 'admin'];

function adminCheck(req, res, next) {
  const admin = req.headers['x-admin-name'] || req.body.createdBy || req.query.admin;
  if (!ALLOWED_ADMINS.includes(admin)) {
    // For read, allow everyone. For write, block
    if (req.method!== 'GET') {
      return res.status(403).json({ error: 'Only Samuel and Monicah can manage inventory' });
    }
  }
  next();
}

router.use(adminCheck);

// GET all shoes for admin table
router.get('/', async (req, res) => {
  const { search, category, brand } = req.query;
  let query = {};
  if (search) query.name = { $regex: search, $options: 'i' };
  if (category) query.category = category;
  if (brand) query.brand = brand;
  const products = await Product.find(query).sort({ createdAt: -1 });
  res.json(products);
});

// ADD shoe
router.post('/', async (req, res) => {
  try {
    const product = await Product.create(req.body);
    res.status(201).json(product);
  } catch(e){ res.status(400).json({ error: e.message }) }
});

// UPDATE shoe
router.put('/:id', async (req, res) => {
  const p = await Product.findByIdAndUpdate(req.params.id, req.body, { new: true });
  res.json(p);
});

// DELETE
router.delete('/:id', async (req, res) => {
  await Product.findByIdAndDelete(req.params.id);
  res.json({ message: 'Deleted' });
});

router.delete('/', async (req, res) => {
  const { ids } = req.body;
  await Product.deleteMany({ _id: { $in: ids } });
  res.json({ message: 'Bulk deleted' });
});

module.exports = router;