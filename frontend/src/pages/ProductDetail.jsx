import React, { useState, useEffect } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { useCart } from '../context/CartContext';

// REMOVE API_URL - not needed for mock data
// const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:5000/api';

export default function ProductDetail() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [shoe, setShoe] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [selectedSize, setSelectedSize] = useState(null);
  const [addedMsg, setAddedMsg] = useState(false);

  const { addToCart, itemCount } = useCart();

  // MOCK SHOES DATABASE - matches Home.jsx mock data
  const MOCK_SHOES = {
    1: {
      id: 1,
      name: "Nike Air Max 270",
      price: 12500,
      description: "The Nike Air Max 270 delivers visible Air under every step. Perfect for all-day comfort.",
      image: "https://images.unsplash.com/photo-1542291026-7eec264c27ff?w=600",
      sizes: [7, 8, 9, 10, 11],
      stock: 15,
      category: "Men",
      brand: "Nike"
    },
    2: {
      id: 2,
      name: "Adidas Ultraboost",
      price: 15800,
      description: "Energy return meets comfort in the Ultraboost. Responsive cushioning for every run.",
      image: "https://images.unsplash.com/photo-1608231387042-66d1773070a5?w=600",
      sizes: [6, 7, 8, 9, 10],
      stock: 8,
      category: "Women",
      brand: "Adidas"
    },
    3: {
      id: 3,
      name: "Puma RS-X",
      price: 9800,
      description: "Bold design meets retro running style. Stand out with chunky silhouette.",
      image: "https://images.unsplash.com/photo-1606107557195-0e29a4b5b4aa?w=600",
      sizes: [8, 9, 10, 11, 12],
      stock: 20,
      category: "Unisex",
      brand: "Puma"
    },
    4: {
      id: 4,
      name: "Jordan 1 Low",
      price: 18900,
      description: "Classic basketball icon in low-top form. Timeless style for any outfit.",
      image: "https://images.unsplash.com/photo-1556906781-9a412961c28c?w=600",
      sizes: [7, 8, 9, 10, 11, 12],
      stock: 5,
      category: "Men",
      brand: "Nike"
    }
  };

  useEffect(() => {
    setLoading(true);
    setError(null);

    // SIMULATE API CALL WITH MOCK DATA
    setTimeout(() => {
      const mockShoe = MOCK_SHOES[id];
      if (mockShoe) {
        setShoe(mockShoe);
        // Auto-select first size if available
        if (mockShoe.sizes?.length > 0) {
          setSelectedSize(mockShoe.sizes[0]);
        }
      } else {
        setError('Product not found');
      }
      setLoading(false);
    }, 300);
  }, [id]);

  const handleAddToCart = () => {
    if (shoe.sizes?.length > 0 &&!selectedSize) {
      alert('Please select a size');
      return;
    }

    addToCart(shoe, selectedSize);
    setAddedMsg(true);
    setTimeout(() => setAddedMsg(false), 2000);
  };

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <div className="text-xl">Loading...</div>
      </div>
    );
  }

  if (error ||!shoe) {
    return (
      <div className="min-h-screen bg-gray-50">
        <Navbar />
        <div className="flex flex-col items-center justify-center py-20">
          <h2 className="text-2xl font-bold mb-4">Product not found</h2>
          <Link to="/" className="px-6 py-3 bg-black text-white rounded-lg hover:bg-gray-800">
            Back to Shop
          </Link>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <Navbar />

      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <button
          onClick={() => navigate(-1)}
          className="text-gray-600 hover:text-gray-900 mb-6 inline-flex items-center gap-1"
        >
          ← Back
        </button>

        <div className="grid md:grid-cols-2 gap-12 bg-white p-8 rounded-lg shadow">
          <div>
            <img
              src={shoe.image}
              alt={shoe.name}
              className="w-full rounded-lg"
              onError={(e) => e.target.src = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="400" height="400"%3E%3Crect width="400" height="400" fill="%23f3f4f6"/%3E%3Ctext x="50%25" y="50%25" dominant-baseline="middle" text-anchor="middle" font-family="sans-serif" font-size="18" fill="%239ca3af"%3ENo Image%3C/text%3E%3C/svg%3E'}
            />
          </div>

          <div>
            <div className="text-xs uppercase tracking-[0.08em] text-gray-500 font-semibold mb-2">
              {shoe.category} {shoe.brand && `· ${shoe.brand}`}
            </div>
            <h1 className="text-4xl font-bold text-gray-900 mb-2">{shoe.name}</h1>
            <p className="text-3xl font-bold text-gray-900 mb-6">KSh {Number(shoe.price).toLocaleString()}</p>

            {shoe.description && (
              <p className="text-gray-600 mb-8 leading-relaxed">{shoe.description}</p>
            )}

            {shoe.sizes?.length > 0 && (
              <div className="mb-8">
                <h3 className="font-semibold mb-3">Select Size</h3>
                <div className="flex flex-wrap gap-2">
                  {shoe.sizes.map(size => (
                    <button
                      key={size}
                      onClick={() => setSelectedSize(size)}
                      className={`px-4 py-2 border rounded-lg transition ${
                        selectedSize === size
                         ? 'bg-black text-white border-black'
                          : 'border-gray-300 hover:border-black'
                      }`}
                    >
                      {size}
                    </button>
                  ))}
                </div>
              </div>
            )}

            {shoe.stock!== undefined && (
              <p className="text-sm text-gray-600 mb-4">
                {shoe.stock > 0? `${shoe.stock} in stock` : 'Out of stock'}
              </p>
            )}

            <button
              onClick={handleAddToCart}
              disabled={shoe.stock === 0}
              className="w-full py-4 bg-black text-white rounded-lg hover:bg-gray-800 disabled:bg-gray-400 disabled:cursor-not-allowed text-lg font-semibold transition relative"
            >
              {shoe.stock === 0? 'Out of Stock' : 'Add to Cart'}
            </button>

            {addedMsg && (
              <div className="mt-4 p-3 bg-green-50 text-green-700 rounded-lg text-center text-sm">
                ✓ Added to cart!
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}

// Reuse same Navbar as other pages
function Navbar() {
  const { itemCount } = useCart();

  return (
    <nav className="bg-white shadow-md sticky top-0 z-10">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16">
          <Link to="/" className="text-2xl font-bold text-gray-900">
            Monique Shoes
          </Link>
          <Link to="/cart" className="relative px-4 py-2 bg-black text-white rounded-lg hover:bg-gray-800 transition">
            Cart ({itemCount})
            {itemCount > 0 && (
              <span className="absolute -top-2 -right-2 bg-red-500 text-white text-xs w-5 h-5 rounded-full flex items-center justify-center">
                {itemCount}
              </span>
            )}
          </Link>
        </div>
      </div>
    </nav>
  );
}