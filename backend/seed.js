const pool = require('./db');

async function seed() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS shoes (
      id SERIAL PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      price DECIMAL(10,2) NOT NULL,
      image_url TEXT,
      description TEXT,
      category VARCHAR(100),
      stock INTEGER DEFAULT 10
    )
  `);

  await pool.query(`
    INSERT INTO shoes (name, price, image_url, description, category, stock) VALUES
    ('Air Max 270', 149.99, 'https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=500', 'Iconic comfort and style', 'sneakers', 10),
    ('Classic Leather Oxford', 199.99, 'https://images.unsplash.com/photo-1614252235316-8c857d38b148?w=500', 'Handcrafted premium leather', 'formal', 5),
    ('Urban Runner', 119.99, 'https://images.unsplash.com/photo-1608231387042-66d1773070a5?w=500', 'Lightweight for daily wear', 'sneakers', 15)
    ON CONFLICT DO NOTHING
  `);
  
  console.log('Shoes seeded!');
  process.exit();
}

seed();