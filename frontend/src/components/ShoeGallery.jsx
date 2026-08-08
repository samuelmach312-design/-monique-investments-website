import { useState, useEffect } from 'react';
import './ShoeGallery.css';

function ShoeGallery({ onAddToCart }) {
  const [shoes, setShoes] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  // Price mapping: shoes 3500-5000, accessories 400-500
  const normalizePrice = (product) => {
    const isAccessory = product.category === 'Shoe Accessories' || 
                       product.category === 'Belts' ||
                       product.name.toLowerCase().includes('lace') ||
                       product.name.toLowerCase().includes('cleaner') ||
                       product.name.toLowerCase().includes('horn');
    
    if (isAccessory) {
      // Accessories: 400-500 range
      const accessoryPrices = [400, 420, 450, 480, 500];
      return accessoryPrices[product.id % accessoryPrices.length];
    } else {
      // Shoes: 3500-5000 range
      const shoePrices = [3500, 3800, 4000, 4200, 4500, 4800, 5000];
      return shoePrices[product.id % shoePrices.length];
    }
  };

  useEffect(() => {
    fetch('http://localhost:3001/api/products')
      .then(res => {
        if (!res.ok) throw new Error('Failed to fetch products');
        return res.json();
      })
      .then(data => {
        // Override prices based on category
        const updatedData = data.map(shoe => ({
          ...shoe,
          price: normalizePrice(shoe)
        }));
        setShoes(updatedData);
        setLoading(false);
      })
      .catch(err => {
        setError(err.message);
        setLoading(false);
      });
  }, []);

  const handleAddToCart = (shoe) => {
    if (!onAddToCart) return;
    
    const imagePath = shoe.image_url || `/images/shoe-${shoe.id}.jpg` || '/images/no-image.png';
    
    onAddToCart({
      id: shoe.id,
      key: shoe.id,
      name: shoe.name,
      price: Number(shoe.price),
      image: imagePath,
      img: imagePath,
      category: shoe.category,
      brand: shoe.brand,
      description: shoe.description,
      sizes: shoe.sizes,
      stock: shoe.stock,
      qty: 1
    });
  };

  if (loading) return <div className="shoe-gallery"><p>Loading shoes...</p></div>;
  if (error) return <div className="shoe-gallery"><p>Error: {error}</p></div>;

  return (
    <div className="shoe-gallery">
      {shoes.map((shoe) => (
        <div className="shoe-item" key={shoe.id}>
          <img 
            src={`/images/shoe-${shoe.id}.jpg`} 
            alt={shoe.name} 
            loading="lazy"
            onError={(e) => {
              e.target.onerror = null; 
              e.target.src = '/images/no-image.png';
            }}
          />
          
          <div className="shoe-info">
            <p className="shoe-category">{shoe.category} · {shoe.brand}</p>
            <h3>{shoe.name}</h3>
            <p className="shoe-desc">{shoe.description}</p>
            <p className="shoe-size">Sizes: {shoe.sizes}</p>
            <p className="shoe-price">KSh {Number(shoe.price).toLocaleString()}</p>
            <p className="shoe-stock">Stock: {shoe.stock}</p>
            <button 
              className="add-to-cart-btn"
              onClick={() => handleAddToCart(shoe)}
              disabled={shoe.stock === 0}
            >
              {shoe.stock === 0 ? 'Out of Stock' : 'Add to Cart'}
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}

export default ShoeGallery;