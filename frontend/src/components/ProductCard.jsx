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
    await new Promise(r => setTimeout(r, 400))
    addToCart(product)
    setIsAdding(false)
    setIsAdded(true)
    setTimeout(() => setIsAdded(false), 2000)
  }

  const img = product.image_url || product.image || FALLBACK;

  return (
    <div className="group bg-white rounded-[1.6rem] border border-gray-100 overflow-hidden hover:border-gray-200 hover:shadow-xl transition-all duration-300 flex flex-col h-full">
      <Link to={`/product/${product.id || product._id}`} className="relative bg-[#f8fafc] aspect-square p-5 flex items-center justify-center overflow-hidden">
        <img
          src={img}
          alt={product.name}
          draggable={false}
          onError={(e)=>{ e.target.onerror=null; e.target.src=FALLBACK; }}
          className="w-full h-full object-contain object-center group-hover:scale-105 transition-transform duration-500"
          loading="lazy"
        />
        <div className="absolute top-3 left-3 bg-white/95 px-3 py-1 rounded-full text- font-black shadow-sm border">
          {product.brand || 'Monique'}
        </div>
        {isAdded && (
          <div className="absolute inset-0 bg-green-500/90 flex items-center justify-center">
            <div className="bg-white rounded-full p-3 shadow-xl">✓</div>
          </div>
        )}
      </Link>
      <div className="p-4 flex flex-col flex-1 gap-2">
        <Link to={`/product/${product.id || product._id}`}>
          <h3 className="text- font-bold text-gray-900 leading-[1.35] line-clamp-2 min-h- hover:text-blue-600 transition-colors">
            {product.name}
          </h3>
        </Link>
        <div className="flex items-center justify-between mt-auto">
          <div>
            <p className="text- font-extrabold">KES {Number(product.price).toLocaleString()}</p>
            <p className="text- text-gray-400 line-through">KES {(Number(product.price)*1.3).toFixed(0)}</p>
          </div>
          <button onClick={handleAddToCart} disabled={isAdding || isAdded} className={`min-w- h-9 rounded-full text- font-black flex items-center justify-center ${isAdded?'bg-green-600 text-white':'bg-[#0f172a] text-white hover:bg-black'}`}>
            {isAdding?'...':isAdded?'Added ✓':'+ Add'}
          </button>
        </div>
      </div>
    </div>
  )
}