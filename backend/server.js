require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');

const app = express();

app.use(cors({ origin: true, credentials: true }));
app.use(express.json({ limit: '10mb' }));

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

app.get('/', (req,res)=> res.json({ status: 'Monique API Running' }));
app.get('/api/mongo-products', async (req,res)=>{
  try { const p = await Product.find().sort({createdAt:-1}); res.json(p); }
  catch(e){ res.status(500).json({error:e.message}) }
});
app.post('/api/mongo-products', async (req,res)=>{
  try {
    const data = {...req.body, price: req.body.sellingPrice||req.body.price};
    const product = new Product(data);
    await product.save();
    console.log('✅ Saved:', product.name);
    res.status(201).json(product);
  } catch(e){ console.error(e); res.status(500).json({error:e.message}) }
});
app.put('/api/mongo-products/:id', async (req,res)=>{
  try { const p = await Product.findByIdAndUpdate(req.params.id, {...req.body, price: req.body.sellingPrice||req.body.price}, {new:true}); res.json(p); }
  catch(e){ res.status(500).json({error:e.message}) }
});
app.delete('/api/mongo-products/:id', async (req,res)=>{
  try { await Product.findByIdAndDelete(req.params.id); res.json({success:true}); }
  catch(e){ res.status(500).json({error:e.message}) }
});

// AUTO CONNECT - Local -> Memory -> Works!
async function startServer(){
  const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/sams-db';
  try {
    await mongoose.connect(MONGO_URI);
    console.log('✅ MongoDB Connected: Local');
  } catch(err){
    console.log('⚠️ Local Mongo failed, starting in-memory Mongo...');
    const { MongoMemoryServer } = require('mongodb-memory-server');
    const mongoServer = await MongoMemoryServer.create();
    const uri = mongoServer.getUri();
    await mongoose.connect(uri);
    console.log('✅ In-Memory MongoDB Started!');
  }
  app.listen(3001, ()=> console.log('🚀 Server running on port 3001'));
}
startServer();