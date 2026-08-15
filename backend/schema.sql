CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  name TEXT, username TEXT UNIQUE, contact TEXT, email TEXT UNIQUE,
  password_hash TEXT, profile_pic_url TEXT, created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE products (
  id SERIAL PRIMARY KEY, name TEXT, category TEXT, brand TEXT,
  description TEXT, price NUMERIC, image_url TEXT, stock INT DEFAULT 0
);

CREATE TABLE cart_items (
  id SERIAL PRIMARY KEY, user_id INT REFERENCES users(id),
  product_id INT REFERENCES products(id), quantity INT DEFAULT 1,
  UNIQUE(user_id, product_id)
);

CREATE TABLE orders (
  id SERIAL PRIMARY KEY, user_id INT REFERENCES users(id),
  total NUMERIC, status TEXT DEFAULT 'pending',
  mpesa_receipt TEXT, created_at TIMESTAMP DEFAULT NOW()
);