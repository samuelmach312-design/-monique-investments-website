import React, { useState } from 'react'
import { useCart } from '../context/CartContext'
import { Link } from 'react-router-dom'

export default function ProductCard({ product }) {
  const { addToCart } = useCart()
  const [isAdding, setIsAdding] = useState(false)
  const [isAdded, setIsAdded] = useState(false)

  const handleAddToCart = async (e) => {
    e.preventDefault()
    e.stopPropagation()

    if (isAdding || isAdded) return

    setIsAdding(true)

    // Simulate adding delay for effect
    await new Promise(resolve => setTimeout(resolve, 600))

    addToCart(product)

    setIsAdding(false)
    setIsAdded(true)

    // Reset after 2 seconds
    setTimeout(() => {
      setIsAdded(false)
    }, 2000)
  }

  return (
    <div className="group bg-white rounded-2xl border border-gray-100 overflow-hidden hover:border-blue-200 hover:shadow-xl hover:shadow-blue-50/50 transition-all duration-300 flex flex-col h-full">
      {/* Image */}
      <Link to={`/product/${product.id || product._id}`} className="relative overflow-hidden bg-[#f8fafc]">
        <img
          src={product.image_url || product.image}
          onContextMenu={(e) => e.preventDefault()}
          alt={product.name}
          draggable={false}
          className="w-full h- md:h- object-cover object-center group-hover:scale-105 transition-transform duration-500"
          loading="lazy"
        />

        {/* Brand badge */}
        <div className="absolute top-2.5 left-2.5 bg-white/90 backdrop-blur-md px-2.5 py-1 rounded-full text- font-bold text-gray-700 shadow-sm border border-gray-100">
          {product.brand}
        </div>

        {/* Added overlay */}
        {isAdded && (
          <div className="absolute inset-0 bg-green-500/90 backdrop-blur-sm flex items-center justify-center animate-in fade-in">
            <div className="bg-white rounded-full p-3 shadow-xl animate-bounce">
              <svg className="w-8 h-8 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="3" d="M5 13l4 4L19 7" />
              </svg>
            </div>
          </div>
        )}
      </Link>

      {/* Info */}
      <div className="p-3.5 flex flex-col flex-1 gap-2.5">
        <Link to={`/product/${product.id || product._id}`}>
          <h3 className="text- font-semibold text-gray-900 leading-[1.35] line-clamp-2 min-h- hover:text-blue-600 transition-colors">
            {product.name}
          </h3>
        </Link>

        <div className="flex items-center justify-between mt-auto">
          <div>
            <p className="text- font-extrabold text-gray-900">
              KES {Number(product.price).toLocaleString()}
            </p>
            <p className="text- text-gray-400 line-through">KES {(Number(product.price) * 1.3).toFixed(0)}</p>
          </div>

          {/* ADD TO CART BUTTON WITH EFFECT */}
          <button
            onClick={handleAddToCart}
            disabled={isAdding || isAdded}
            className={`relative min-w- h-9 rounded-full text- font-bold tracking-wide transition-all duration-200 flex items-center justify-center gap-1.5 overflow-hidden ${
              isAdded
               ? 'bg-green-600 text-white shadow-lg shadow-green-200'
                : isAdding
               ? 'bg-gray-900 text-white'
                : 'bg-[#0f172a] text-white hover:bg-black hover:shadow-lg hover:shadow-gray-900/20 active:scale-95'
            }`}
          >
            {isAdding? (
              <>
                <span className="w-3.5 h-3.5 border-2 border-white/30 border-t-white rounded-full animate-spin"></span>
                Adding
              </>
            ) : isAdded? (
              <>
                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="3" d="M5 13l4 4L19 7" />
                </svg>
                Added
              </>
            ) : (
              <>
                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                </svg>
                Add
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  )
}