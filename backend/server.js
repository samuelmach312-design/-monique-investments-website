require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const { neon } = require('@neondatabase/serverless');

const app = express();
app.use(cors({ origin: true, credentials: true }));
app.use(express.json());

// Ensure uploads exist - both locations
const uploadDir1 = path.join(__dirname, 'uploads');
const uploadDir2 = path.join(__dirname, 'public/uploads');
if (!fs.existsSync(uploadDir1)) fs.mkdirSync(uploadDir1, { recursive: true });
if (!fs.existsSync(uploadDir2)) fs.mkdirSync(uploadDir2, { recursive: true });

app.use('/uploads', express.static(uploadDir1));
app.use('/uploads', express.static(uploadDir2));
app.use('/images', express.static(uploadDir1));
app.use('/images', express.static(uploadDir2));
app.use('/public/uploads', express.static(uploadDir2));

const sql = process.env.DATABASE_URL ? neon(process.env.DATABASE_URL) : null;

app.get('/', (req,res)=> res.json({ status: 'Neon API Running', hasDB: !!sql }));

// Both routes point to same handler
async function getProductsHandler(req,res){
  try {
    if (!sql) return res.json({ success: true, products: [] });
    const products = await sql`SELECT * FROM products WHERE in_stock = true ORDER BY id DESC`;
    const formatted = products.map(p => ({
      id: p.id, _id: p.id, name: p.name, brand: p.brand, category: p.category,
      price: Number(p.price), sellingPrice: Number(p.price), 
      sizes: '40-45', size: '40-45', stock: 50, in_stock: true,
      image: p.image_url, image_url: p.image_url, description: p.name || p.description
    }));
    res.json({ success: true, products: formatted });
  } catch(e) { 
    console.error(e);
    res.status(500).json({ success: false, error: e.message }); 
  }
}

app.get('/api/products', getProductsHandler);
app.get('/api/mongo-products', getProductsHandler);

// Use the full products router for POST/PUT/DELETE with uploads
const productsRouter = require('./routes/products');
app.use('/api/products', productsRouter);
app.use('/api/mongo-products', productsRouter);

const PORT = process.env.PORT || 3001;
app.listen(PORT, ()=> console.log(`🚀 Server on port ${PORT}, DB: ${!!sql}`));
