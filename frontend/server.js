require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');

const app = express();

// ===== CORS - FIXES YOUR NETWORK ERROR =====
const allowedOrigins = [
  'https://monique-investments.vercel.app',
  'https://sams-project-website.onrender.com',
  'http://localhost:5173',
  'http://localhost:3000',
  'http://localhost:5174'
];

app.use(cors({
  origin: function(origin, callback){
    if(!origin) return callback(null, true);
    if(allowedOrigins.includes(origin) || origin.endsWith('.vercel.app')) return callback(null, true);
    return callback(null, true); // allow all for now to fix your issue
  },
  methods: ['GET','POST','PUT','DELETE','OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  credentials: true
}));

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// ===== MONGODB =====
const MONGO_URI = process.env.MONGO_URI || process.env.MONGODB_URI;
if(!MONGO_URI) console.log('❌ MONGO_URI missing in .env');

mongoose.connect(MONGO_URI)
  .then(()=> console.log('✅ MongoDB Connected'))
  .catch(err=> console.error('❌ Mongo Error:', err.message));

// ===== SCHEMAS =====
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

// ===== ROUTES =====
app.get('/', (req,res)=> res.json({ status: 'Monique Investments API Running', time: new Date() }));

app.get('/api/health', (req,res)=> res.json({ ok: true, db: mongoose.connection.readyState }));

// GET ALL PRODUCTS
app.get('/api/mongo-products', async (req,res)=>{
  try {
    const products = await Product.find().sort({ createdAt: -1 });
    res.json(products);
  } catch(e){
    res.status(500).json({ error: e.message });
  }
});

// CREATE PRODUCT - FIXES YOUR ADMIN CREATE
app.post('/api/mongo-products', async (req,res)=>{
  try {
    console.log('Creating product:', req.body);
    const data = {
      ...req.body,
      price: req.body.sellingPrice || req.body.price,
      sellingPrice: req.body.sellingPrice || req.body.price
    };
    const product = new Product(data);
    await product.save();
    console.log('✅ Product saved:', product._id);
    res.status(201).json(product);
  } catch(e){
    console.error('❌ Create error:', e.message);
    res.status(500).json({ error: e.message });
  }
});

// UPDATE PRODUCT
app.put('/api/mongo-products/:id', async (req,res)=>{
  try {
    const data = {
      ...req.body,
      price: req.body.sellingPrice || req.body.price
    };
    const product = await Product.findByIdAndUpdate(req.params.id, data, { new: true });
    if(!product) return res.status(404).json({ error: 'Not found' });
    res.json(product);
  } catch(e){
    res.status(500).json({ error: e.message });
  }
});

// DELETE PRODUCT
app.delete('/api/mongo-products/:id', async (req,res)=>{
  try {
    await Product.findByIdAndDelete(req.params.id);
    res.json({ success: true });
  } catch(e){
    res.status(500).json({ error: e.message });
  }
});

// Optional: Get single product
app.get('/api/mongo-products/:id', async (req,res)=>{
  try {
    const p = await Product.findById(req.params.id);
    res.json(p);
  } catch(e){ res.status(404).json({ error: 'Not found' }) }
});

// ===== START =====
const PORT = process.env.PORT || 3001;
app.listen(PORT, ()=> console.log(`🚀 Server running on port ${PORT}`));