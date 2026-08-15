const express = require('express');
const router = express.Router();
const Product = require('../models/Product');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { neon } = require('@neondatabase/serverless');

const ALLOWED_ADMINS = ['Samuel', 'Monicah', 'samuel', 'monicah', 'admin'];
function adminCheck(req, res, next) {
  const admin = req.headers['x-admin-name'] || req.body.createdBy || req.query.admin;
  if (!ALLOWED_ADMINS.includes(admin) && req.method!== 'GET') {
    return res.status(403).json({ error: 'Only Samuel and Monicah can manage inventory' });
  }
  next();
}
router.use(adminCheck);

const uploadDir = path.join(__dirname, '../uploads');
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });
const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => cb(null, Date.now() + '-' + file.originalname)
});
const upload = multer({ storage });

// GET all products - Tries Neon first (your 38 products), fallback to Mongo
router.get('/', async (req, res) => {
  try {
    if (process.env.DATABASE_URL) {
      const sql = neon(process.env.DATABASE_URL);
      const products = await sql`SELECT * FROM products WHERE in_stock = true ORDER BY id DESC`;
      // Convert to format your frontend expects
      const formatted = products.map(p => ({
        id: p.id,
        _id: p.id,
        name: p.name,
        brand: p.brand,
        price: p.price,
        sellingPrice: p.price,
        category: p.category,
        image: p.image_url,
        image_url: p.image_url,
        description: p.name,
        stock: 50,
        isActive: true
      }));
      return res.json({ success: true, products: formatted });
    }
    // Fallback to Mongo if no DATABASE_URL
    const { search, category, brand } = req.query;
    let query = {};
    if (search) query.name = { $regex: search, $options: 'i' };
    if (category) query.category = category;
    if (brand) query.brand = brand;
    const products = await Product.find(query).sort({ createdAt: -1 });
    res.json({ success: true, products });
  } catch(e){ res.status(500).json({ success: false, error: e.message }) }
});

router.post('/', upload.single('image'), async (req, res) => {
  try {
    if (process.env.DATABASE_URL) {
      const sql = neon(process.env.DATABASE_URL);
      let imagePath = req.body.image || req.body.image_url || '';
      if (req.file) imagePath = `/uploads/${req.file.filename}`;
      const result = await sql`
        INSERT INTO products (name, brand, price, category, image_url, in_stock)
        VALUES (${req.body.name}, ${req.body.brand || 'Monique'}, ${Number(req.body.price)}, ${req.body.category || 'Shoes'}, ${imagePath}, true)
        RETURNING *
      `;
      return res.status(201).json(result[0]);
    }
    let imagePath = req.body.image;
    if (req.file) imagePath = `/uploads/${req.file.filename}`;
    const product = await Product.create({...req.body, image: imagePath });
    res.status(201).json(product);
  } catch(e){ res.status(400).json({ error: e.message }) }
});

router.put('/:id', upload.single('image'), async (req, res) => {
  try {
    let updateData = {...req.body };
    if (req.file) updateData.image = `/uploads/${req.file.filename}`;
    const p = await Product.findByIdAndUpdate(req.params.id, updateData, { new: true });
    res.json(p);
  } catch(e){ res.status(400).json({ error: e.message }) }
});

router.delete('/:id', async (req, res) => {
  try {
    if (process.env.DATABASE_URL) {
      const sql = neon(process.env.DATABASE_URL);
      await sql`DELETE FROM products WHERE id = ${Number(req.params.id)}`;
      return res.json({ message: 'Deleted from Neon' });
    }
    await Product.findByIdAndDelete(req.params.id);
    res.json({ message: 'Deleted' });
  } catch(e){ res.status(500).json({ error: e.message }) }
});

module.exports = router;