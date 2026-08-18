const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const { neon } = require('@neondatabase/serverless');

const ALLOWED_ADMINS = ['Samuel', 'Monicah', 'samuel', 'monicah', 'admin', 'SAMUEL'];
function adminCheck(req, res, next) {
  if (req.method === 'GET') return next();
  const admin = req.headers['x-admin-name'] || req.body.createdBy || req.query.admin || req.body.admin;
  if (!ALLOWED_ADMINS.includes(admin)) {
    console.log('Blocked admin attempt:', admin);
    // Allow for now but log - change to 403 if you want strict
    // return res.status(403).json({ error: 'Only Samuel and Monicah can manage inventory' });
  }
  next();
}
router.use(adminCheck);

const uploadDir = path.join(__dirname, '../uploads');
const uploadDir2 = path.join(__dirname, '../public/uploads');
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });
if (!fs.existsSync(uploadDir2)) fs.mkdirSync(uploadDir2, { recursive: true });

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    // save to both places so server.js finds it
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const safe = Date.now() + '-' + file.originalname.replace(/[^a-zA-Z0-9.-]/g, '_');
    cb(null, safe);
  }
});
const upload = multer({ 
  storage,
  limits: { fileSize: 10 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) cb(null, true);
    else cb(new Error('Only images allowed'), false);
  }
});

// GET - handled in server.js too, but keep here
router.get('/', async (req, res) => {
  try {
    if (process.env.DATABASE_URL) {
      const sql = neon(process.env.DATABASE_URL);
      const products = await sql`SELECT * FROM products WHERE in_stock = true ORDER BY id DESC`;
      const formatted = products.map(p => ({
        id: p.id, _id: p.id, name: p.name, brand: p.brand, price: p.price,
        sellingPrice: p.price, category: p.category,
        image: p.image_url, image_url: p.image_url, description: p.name, stock: 50
      }));
      return res.json({ success: true, products: formatted });
    }
    return res.json({ success: true, products: [] });
  } catch(e){ res.status(500).json({ success: false, error: e.message }) }
});

router.post('/', upload.single('image'), async (req, res) => {
  try {
    let imagePath = req.body.image || req.body.image_url || '';
    if (req.file) {
      imagePath = `/uploads/${req.file.filename}`;
      // also copy to public/uploads for server.js static
      const src = path.join(uploadDir, req.file.filename);
      const dest = path.join(uploadDir2, req.file.filename);
      try { fs.copyFileSync(src, dest); } catch {}
    }

    if (process.env.DATABASE_URL) {
      const sql = neon(process.env.DATABASE_URL);
      const result = await sql`
        INSERT INTO products (name, brand, price, category, image_url, in_stock, description)
        VALUES (${req.body.name}, ${req.body.brand || 'Monique'}, ${Number(req.body.price) || 0}, ${req.body.category || 'Shoes'}, ${imagePath}, true, ${req.body.description || req.body.name})
        RETURNING *
      `;
      const p = result[0];
      return res.status(201).json({
        id: p.id, _id: p.id, name: p.name, brand: p.brand, price: p.price,
        image: p.image_url, image_url: p.image_url, success: true
      });
    }
    res.status(201).json({ success: true, image: imagePath, name: req.body.name });
  } catch(e){ 
    console.error('POST error', e);
    res.status(400).json({ error: e.message }) 
  }
});

router.delete('/:id', async (req, res) => {
  try {
    if (process.env.DATABASE_URL) {
      const sql = neon(process.env.DATABASE_URL);
      await sql`DELETE FROM products WHERE id = ${Number(req.params.id)}`;
      return res.json({ message: 'Deleted from Neon', success: true });
    }
    res.json({ message: 'Deleted', success: true });
  } catch(e){ res.status(500).json({ error: e.message }) }
});

module.exports = router;
