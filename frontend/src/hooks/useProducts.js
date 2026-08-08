import { useState, useEffect } from 'react';

const SHEET_URL = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vSngq0QRyOxcZRzzS51ajBfQj9fJC4b2KDaO8RVeFA1eX9EhzRqFZQXLrSu0YHkYWZBOExx8FAh3of1/pub?gid=0&single=true&output=csv';
// Replace YOUR_SHEET_ID with your actual published csv link

export function useProducts() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  useEffect(() => {
    async function fetchProducts() {
      try {
        // Cache for 5 min to save data bundles
        const cached = localStorage.getItem('products_cache');
        const cacheTime = localStorage.getItem('products_cache_time');
        
        if (cached && cacheTime && Date.now() - cacheTime < 300000) {
          setProducts(JSON.parse(cached));
          setLoading(false);
          return;
        }

        const res = await fetch(SHEET_URL);
        if (!res.ok) throw new Error('Failed to fetch sheet');
        
        const csvText = await res.text();
        const rows = csvText.split('\n').slice(1); // skip header
        
        const parsed = rows
          .filter(row => row.trim()) // remove empty rows
          .map(row => {
            const [id, name, price, imageUrl, description, inStock] = row.split(',');
            return {
              id: id?.trim(),
              name: name?.trim(),
              price: parseFloat(price) || 0,
              imageUrl: imageUrl?.trim(),
              description: description?.trim(),
              inStock: inStock?.trim().toUpperCase() === 'TRUE'
            };
          });

        localStorage.setItem('products_cache', JSON.stringify(parsed));
        localStorage.setItem('products_cache_time', Date.now());
        setProducts(parsed);
      } catch (err) {
        setError(err.message);
        // Fallback to cache if fetch fails
        const cached = localStorage.getItem('products_cache');
        if (cached) setProducts(JSON.parse(cached));
      } finally {
        setLoading(false);
      }
    }

    fetchProducts();
  }, []);

  return { products, loading, error };
}
