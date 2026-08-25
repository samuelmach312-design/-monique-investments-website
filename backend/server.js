require('dotenv').config();
const express = require('express');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const { neon } = require('@neondatabase/serverless');
const { checkAdmin } = require('./middleware/auth');

const app = express();

// 1. MIDDLEWARE
app.use(cors({ origin: true, credentials: true }));
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Uploads
const uploadDir1 = path.join(__dirname, 'uploads');
const uploadDir2 = path.join(__dirname, 'public/uploads');
if (!fs.existsSync(uploadDir1)) fs.mkdirSync(uploadDir1, { recursive: true });
if (!fs.existsSync(uploadDir2)) fs.mkdirSync(uploadDir2, { recursive: true });

app.use('/uploads', express.static(uploadDir1));
app.use('/uploads', express.static(uploadDir2));
app.use('/images', express.static(uploadDir1));
app.use('/public/uploads', express.static(uploadDir2));

const sql = process.env.DATABASE_URL ? neon(process.env.DATABASE_URL) : null;

// --- API HEALTH CHECK (move to /api so it doesn't block frontend) ---
app.get('/api', (req,res)=> res.json({ 
  status: 'Monique Neon API Running', 
  hasDB: !!sql,
  admins: ['Samuel - 0706631292', 'Monicah - 0723808067']
}));

async function getProductsHandler(req,res){
  try {
    if (!sql) return res.json({ success: true, products: []});
    const products = await sql`SELECT * FROM products WHERE in_stock = true ORDER BY id DESC`;
    const formatted = products.map(p => ({
      id: p.id, _id: p.id, name: p.name, brand: p.brand, category: p.category,
      price: Number(p.price), sellingPrice: Number(p.price), 
      sizes: '40-45', size: '40-45', stock: 50, in_stock: true,
      image: p.image_url, image_url: p.image_url, description: p.description || p.name
    }));
    res.json({ success: true, products: formatted });
  } catch(e) { 
    console.error(e);
    res.status(500).json({ success: false, error: e.message}); 
  }
}

// PUBLIC GET
app.get('/api/products', getProductsHandler);
app.get('/api/mongo-products', getProductsHandler);

// AUTH ROUTES
const authRoutes = require('./routes/auth')
app.use('/api/auth', authRoutes)

// PROTECTED WRITE ROUTES
const productsRouter = require('./routes/products');
app.use('/api/products', checkAdmin, productsRouter);
app.use('/api/mongo-products', checkAdmin, productsRouter);

// --- 2. SERVE FRONTEND (THIS FIXES YOUR 404) ---
// Vite builds to 'dist', CRA builds to 'build' - we check both
const distPath = path.join(__dirname, 'dist');
const buildPath = path.join(__dirname, 'build');
const frontendPath = fs.existsSync(distPath) ? distPath : buildPath;

if (fs.existsSync(frontendPath)) {
  app.use(express.static(frontendPath));
  console.log(`✅ Serving frontend from ${frontendPath}`);
  
  // For any route not starting with /api, serve React app (fixes /admin, /cart, etc)
  app.get('*', (req, res) => {
    if (req.path.startsWith('/api') || req.path.startsWith('/uploads')) {
      return res.status(404).json({ error: 'Not found' });
    }
    res.sendFile(path.join(frontendPath, 'index.html'));
  });
} else {
  console.log('⚠️ No frontend build found at dist/ or build/');
  app.get('/', (req,res)=> res.json({ status: 'API only - frontend not built' }));
}

const PORT = process.env.PORT || 10000;
app.listen(PORT, ()=> console.log(`🚀 Monique Server on ${PORT}, DB: ${!!sql}, Frontend: ${fs.existsSync(frontendPath)}`));