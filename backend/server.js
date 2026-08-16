require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const { neon } = require('@neondatabase/serverless');

const app = express();
app.use(cors({ origin: true, credentials: true }));
app.use(express.json());
app.use('/images', express.static(path.join(__dirname, 'public/uploads')));
app.use('/uploads', express.static(path.join(__dirname, 'public/uploads')));

const sql = neon(process.env.DATABASE_URL);

app.get('/', (req,res)=> res.json({ status: 'Neon API Running' }));

app.get('/api/products', async (req,res)=>{
  try {
    const products = await sql`SELECT * FROM products WHERE in_stock = true ORDER BY id DESC`;
    const formatted = products.map(p => ({
      id: p.id, _id: p.id, name: p.name, brand: p.brand, category: p.category,
      price: Number(p.price), sellingPrice: Number(p.price), size: '40-45', stock: 50,
      image: p.image_url, image_url: p.image_url, description: p.name
    }));
    res.json({ success: true, products: formatted });
  } catch(e) { res.status(500).json({ error: e.message }); }
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, ()=> console.log(`🚀 Neon Server on port ${PORT}`));