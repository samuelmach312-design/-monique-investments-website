const { Pool } = require('pg');
require('dotenv').config();

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: process.env.DB_PORT || 5433,
  user: process.env.DB_USER || 'postgres',
  password: String(process.env.DB_PASSWORD || 'sam123'), // force string
  database: process.env.DB_NAME || 'monique_db'
});

module.exports = pool;