require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const path = require('path');
const fs = require('fs');

const app = express();

app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// uploads static
const uploadDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });
app.use('/uploads', express.static(uploadDir));

// --- NEON SETUP ---
let sql = null;
let pool = null;
if (process.env.DATABASE_URL) {
  try {
    // Try @neondatabase/serverless first
    const { neon } = require('@neondatabase/serverless');
    sql = neon(process.env.DATABASE_URL);
    console.log('✅ Neon connected with @neondatabase/serverless');
  } catch (e) {
    // Fallback to pg
    const { Pool } = require('pg');
    pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: { rejectUnauthorized: false } });
    console.log('✅ Neon connected with pg Pool');
  }
}

// Mongoose Product for fallback
const productSchema = new mongoose.Schema({
  name: { type: String, required: true },
  brand: { type: String, default: 'Monique' },
  category: { type: String, default: 'Shoes' },
  size: { type: String, default: '42' },
  sellingPrice: { type: Number, required: true },
  price: { type: Number },
  stock: { type: Number, default: 10 },
  image: { type: String, default: '' },
  description: { type: String, default: '' }
}, { timestamps: true });
const Product = mongoose.models.Product || mongoose.model('Product', productSchema);

// --- MAIN ROUTE: /api/products - NOW READS FROM NEON ---
app.get('/api/products', async (req, res) => {
  try {
    if (sql) {
      const products = await sql`SELECT * FROM products WHERE in_stock = true ORDER BY id DESC`;
      const formatted = products.map(p => ({
        id: p.id,
        _id: p.id,
        name: p.name,
        brand: p.brand,
        category: p.category,
        price: Number(p.price),
        sellingPrice: Number(p.price),
        size: '40-45',
        stock: 50,
        image: p.image_url,
        image_url: p.image_url,
        description: p.name
      }));
      console.log(`✅ Returning ${formatted.length} products from Neon`);
      return res.json({ success: true, products: formatted });
    }
    if (pool) {
      const result = await pool.query('SELECT * FROM products WHERE in_stock = true ORDER BY id DESC');
      const formatted = result.rows.map(p => ({
        id: p.id, _id: p.id, name: p.name, brand: p.brand, category: p.category,
        price: Number(p.price), sellingPrice: Number(p.price), size: '40-45', stock: 50,
        image: p.image_url, image_url: p.image_url, description: p.name
      }));
      return res.json({ success: true, products: formatted });
    }
    // Fallback to Mongo
    const mongoProducts = await Product.find().sort({ createdAt: -1 });
    res.json({ success: true, products: mongoProducts });
  } catch (e) {
    console.error('❌ /api/products error:', e);
    res.status(500).json({ success: false, error: e.message });
  }
});

// Try load external router if exists
try {
  const productRoutes = require('./routes/products');
  app.use('/api/products-mongo', productRoutes);
  console.log('✅ /api/products-mongo router loaded');
} catch(e) {
  console.log('⚠ external products router not found - using inline Neon route');
}

app.get('/', (req,res)=> res.json({ status: 'Monique API Running on 3001 - Neon Ready' }));

// Keep old mongo routes
app.get('/api/mongo-products', async (req,res)=>{
  try { const p = await Product.find().sort({createdAt:-1}); res.json(p); }
  catch(e){ res.status(500).json({error:e.message}) }
});