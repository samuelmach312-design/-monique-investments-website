import React, { useState } from 'react'
import { useCart } from '../context/CartContext'
import { Link } from 'react-router-dom'

const FALLBACK = '/images/monique-logo.png';

export default function ProductCard({ product }) {
  const { addToCart } = useCart()
  const [isAdding, setIsAdding] = useState(false)
  const [isAdded, setIsAdded] = useState(false)

  const handleAddToCart = async (e) => {
    e.preventDefault()
    e.stopPropagation()
    if (isAdding || isAdded) return
    setIsAdding(true)
    await new Promise(r => setTimeout(r, 300))
    addToCart(product)
    setIsAdding(false)
    setIsAdded(true)
    setTimeout(() => setIsAdded(false), 1200)
  }

  const img = product.image_url || product.image || FALLBACK;
  const price = Number(product.price);
  const oldPrice = Math.round(price * 1.3);
  const discount = 23; // Jumia style

  return (
    <div className="group bg-white rounded-lg border border-gray-100 hover:shadow-[0_4px_12px_rgba(0,0,0,0.08)] hover:border-gray-200 transition-all duration-200 flex flex-col overflow-hidden h-full">
      {/* Image - Jumia style: small, centered, white bg */}
      <Link to={`/product/${product.id || product._id}`} className="relative bg-white h-40 md:h-48 flex items-center justify-center p-3 overflow-hidden">
        <img
          src={img}
          alt={product.name}
          loading="lazy"
          draggable={false}
          onError={(e)=>{ e.target.onerror=null; e.target.src=FALLBACK; }}
          className="max-w-[78%] max-h-[78%] w-auto h-auto object-contain object-center group-hover:scale-[1.02] transition-transform duration-200"
        />
        {/* Jumia style discount badge - top right orange */}
        <div className="absolute top-2 right-2 bg-[#feefde] text-[#f68b1e] text-[11px] font-bold px-1.5 py-0.5 rounded">
          -{discount}%
        </div>
        {/* Brand top left subtle */}
        <div className="absolute top-2 left-2 bg-white/90 text-[9px] font-bold px-1.5 py-0.5 rounded border text-gray-600">
          {product.brand || 'Monique'}
        </div>
        {isAdded && (
          <div className="absolute inset-0 bg-black/70 flex items-center justify-center text-white font-bold text-xs">
            ✓ Added to Cart
          </div>
        )}
      </Link>

      {/* Details - Jumia style */}
      <div className="p-2.5 flex flex-col flex-1 gap-1">
        <Link to={`/product/${product.id || product._id}`} className="flex-1">
          <h3 className="text-[13px] leading-[1.3] text-[#313133] line-clamp-2 min-h-[34px] font-normal">
            {product.name}
          </h3>
        </Link>
        
        <div className="mt-1">
          <p className="text-[14px] font-bold text-[#000]">KES {price.toLocaleString()}</p>
          <div className="flex items-center gap-1.5 mt-0.5">
            <p className="text-[12px] text-[#75757a] line-through">KES {oldPrice.toLocaleString()}</p>
          </div>
        </div>

        {/* Jumia style Add button - full width orange */}
        <button 
          onClick={handleAddToCart} 
          disabled={isAdding||isAdded} 
          className={`mt-2 w-full h-8 rounded text-[12px] font-bold uppercase tracking-wide transition-colors ${
            isAdded
              ? 'bg-green-600 text-white' 
              : 'bg-[#f68b1e] hover:bg-[#e07e1b] text-white shadow-sm'
          }`}
        >
          {isAdding ? '...' : isAdded ? '✓ ADDED' : 'ADD TO CART'}
        </button>
      </div>
    </div>
  )
}
