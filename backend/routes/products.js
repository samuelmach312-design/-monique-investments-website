const express = require('express');
const router = express.Router();
const Product = require('../models/Product');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

// Only allow Samuel and Monicah
const ALLOWED_ADMINS = ['Samuel', 'Monicah', 'samuel', 'monicah', 'admin'];

function adminCheck(req, res, next) {
  const admin = req.headers['x-admin-name'] || req.body.createdBy || req.query.admin || req.body.adminName;
  if (!ALLOWED_ADMINS.includes(admin)) {
    if (req.method !== 'GET') {
      return res.status(403).json({ error: 'Only Samuel and Monicah can manage inventory' });
    }
  }
  next();
}

router.use(adminCheck);

// Setup upload folder
const uploadDir = path.join(__dirname, '../uploads');
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => cb(null, Date.now() + '-' + file.originalname)
});
const upload = multer({ storage });

// GET all shoes for admin table
router.get('/', async (req, res) => {
  try {
    const { search, category, brand } = req.query;
    let query = {};
    if (search) query.name = { $regex: search, $options: 'i' };
    if (category) query.category = category;
    if (brand) query.brand = brand;
    const products = await Product.find(query).sort({ createdAt: -1 });
    res.json(products);
  } catch(e){ res.status(500).json({ error: e.message }) }
});

// ADD shoe - with file upload
router.post('/', upload.single('image'), async (req, res) => {
  try {
    let imagePath = req.body.image;
    if (req.file) {
      imagePath = `/uploads/${req.file.filename}`;
    }

    const productData = {
      ...req.body,
      image: imagePath,
      images: imagePath ? [imagePath] : [],
    };

    const product = await Product.create(productData);
    res.status(201).json(product);
  } catch(e){ 
    console.log(e);
    res.status(400).json({ error: e.message }) 
  }
});

// UPDATE shoe - with file upload
router.put('/:id', upload.single('image'), async (req, res) => {
  try {
    let updateData = { ...req.body };
    if (req.file) {
      updateData.image = `/uploads/${req.file.filename}`;
    }
    const p = await Product.findByIdAndUpdate(req.params.id, updateData, { new: true });
    res.json(p);
  } catch(e){ res.status(400).json({ error: e.message }) }
});

// DELETE single
router.delete('/:id', async (req, res) => {
  await Product.findByIdAndDelete(req.params.id);
  res.json({ message: 'Deleted' });
});

// BULK DELETE
router.delete('/', async (req, res) => {
  const { ids } = req.body;
  if(!ids || !ids.length) return res.status(400).json({ error: 'No ids' });
  await Product.deleteMany({ _id: { $in: ids } });
  res.json({ message: 'Bulk deleted' });
});

module.exports = router;