require('dotenv').config();
const express = require('express');
const cors = require('cors');
const { neon } = require('@neondatabase/serverless');

const app = express();
app.use(cors({ origin: true, credentials: true }));
app.use(express.json());

const sql = neon(process.env.DATABASE_URL);

app.get('/', (req,res)=> res.json({ status: 'Neon API Running' }));

app.get('/api/products', async (req,res)=>{
  try {
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
    console.log(`✅ Returning ${formatted.length} products`);
    res.json({ success: true, products: formatted });
  } catch(e) {
    console.error(e);
    res.status(500).json({ error: e.message });
  }
});

app.listen(3001, ()=> console.log('🚀 Neon Server running on http://localhost:3001 - Try /api/products'));