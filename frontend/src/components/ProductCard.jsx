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
    await new Promise(r => setTimeout(r, 350))
    addToCart(product)
    setIsAdding(false)
    setIsAdded(true)
    setTimeout(() => setIsAdded(false), 1500)
  }

  const img = product.image_url || product.image || FALLBACK;

  return (
    <div className="group bg-white rounded-[1.4rem] border border-gray-100 overflow-hidden hover:shadow-lg transition-all flex flex-col h-full">
      <Link to={`/product/${product.id || product._id}`} className="relative bg-[#f8fafc] h- md:h- flex items-center justify-center p-5 overflow-hidden">
        <img
          src={img}
          alt={product.name}
          loading="lazy"
          draggable={false}
          onError={(e)=>{ e.target.onerror=null; e.target.src=FALLBACK; }}
          className="max-w-[72%] max-h-[72%] w-auto h-auto object-contain object-center"
          style={{transform: 'translateZ(0)'}}
        />
        <div className="absolute top-2.5 left-2.5 bg-white px-2.5 py-1 rounded-full text- font-black border shadow-sm">
          {product.brand || 'Monique'}
        </div>
        {isAdded && (
          <div className="absolute inset-0 bg-green-600/90 flex items-center justify-center text-white font-black text-">
            ✓ Added
          </div>
        )}
      </Link>

      <div className="p-3.5 flex flex-col flex-1 gap-2">
        <Link to={`/product/${product.id || product._id}`}>
          <h3 className="text-[12.5px] font-bold leading-[1.35] line-clamp-2 min-h- hover:text-blue-600">
            {product.name}
          </h3>
        </Link>
        <div className="flex items-center justify-between mt-auto">
          <div>
            <p className="text- font-extrabold">KES {Number(product.price).toLocaleString()}</p>
            <p className="text- text-gray-400 line-through">KES {Math.round(Number(product.price)*1.3)}</p>
          </div>
          <button onClick={handleAddToCart} disabled={isAdding||isAdded} className={`h-8 min-w- rounded-full text- font-black px-3.5 ${isAdded?'bg-green-600 text-white':'bg-[#0f172a] text-white hover:bg-black'}`}>
            {isAdding?'...':isAdded?'✓':'Add'}
          </button>
        </div>
      </div>
    </div>
  )
}