import React from 'react'
import './ProductCard.css'
import { useCart } from '../context/CartContext'

export default function ProductCard({ product }) {
  const { addToCart } = useCart()

  const handleAddToCart = (e) => {
    e.preventDefault()
    e.stopPropagation()
    addToCart(product)
  }

  // DEBUG: Remove this after images work
  console.log('Product image:', product.image_url)

  return (
    <div className="product-card">
      <div className="product-card-image">
        <img 
          src={product.image_url} // THIS WAS THE BUG - you had product.image
          alt={product.name}
          loading="lazy"
          onError={(e) => {
            console.log('Image failed to load:', product.image_url)
            e.target.src = 'https://via.placeholder.com/300x300/f3f4f6/9ca3af?text=No+Image'
          }}
        />
      </div>
      <div className="product-card-info">
        <p className="product-card-brand">
          {product.brand || 'LIFESTYLE · MONIQUE'}
        </p>
        <h3 className="product-card-name">
          {product.name}
        </h3>
        <p className="product-card-price">
          KSh {Number(product.price).toLocaleString()}
        </p>
        <button 
          className="product-card-btn"
          onClick={handleAddToCart}
        >
          Add to Cart
        </button>
      </div>
    </div>
  )
}

