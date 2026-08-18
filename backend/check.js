require('dotenv').config();
const { neon } = require('@neondatabase/serverless');
const sql = neon(process.env.DATABASE_URL);

async function run(){
  let samba = await sql`SELECT id, name, in_stock FROM products WHERE name ILIKE '%samba%'`;
  console.log('Before:', samba);
  if(samba.length === 0){
    await sql`INSERT INTO products (name, brand, category, price, image_url, in_stock) VALUES ('Adidas Samba Black White', 'Adidas', 'Shoes', 3500, 'https://monique-investments-website.onrender.com/images/samba.jpg', true)`;
    console.log('Created new Samba!');
  } else {
    await sql`UPDATE products SET in_stock=true, image_url='https://monique-investments-website.onrender.com/images/samba.jpg' WHERE name ILIKE '%samba%'`;
    console.log('Unhidden Samba!');
  }
  const count = await sql`SELECT COUNT(*) as total FROM products WHERE in_stock=true`;
  console.log('Now you have:', count[0].total, 'products');
}
run();