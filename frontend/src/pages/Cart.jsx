import React from 'react'
import { useCart } from '../context/CartContext'
import { Link, useNavigate } from 'react-router-dom'
import { Trash2, Plus, Minus } from 'lucide-react'

export default function Cart() {
  const { cart, removeFromCart, updateQty, clearCart, total, itemCount } = useCart()
  const navigate = useNavigate()

  const handleCheckout = () => {
    navigate('/checkout')
  }

  if (cart.length === 0) {
    return (
      <div className="min-h-screen bg-[#f5f5f7] flex items-center justify-center p-4">
        <div className="text-center">
          <h2 className="text-2xl font-bold text-gray-900 mb-4">Your Cart is Empty</h2>
          <p className="text-gray-500 mb-8">Add some products to get started</p>
          <Link
            to="/"
            className="inline-block px-6 py-3 bg-gray-900 text-white rounded-lg font-semibold hover:bg-black transition-all"
          >
            Continue Shopping
          </Link>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-[#f5f5f7]">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-3xl font-bold text-gray-900">
            Shopping Cart {itemCount > 0 && `(${itemCount})`}
          </h1>
          <button
            onClick={clearCart}
            className="text-sm text-red-600 hover:text-red-700 font-medium transition-colors"
          >
            Clear Cart
          </button>
        </div>

        <div className="grid lg:grid-cols-3 gap-8">
          {/* Cart Items */}
          <div className="lg:col-span-2 space-y-4">
            {cart.map((item) => {
              const price = Number(item.price) || 0
              const qty = Number(item.qty) || 1
              const itemTotal = price * qty

              return (
                <div key={item.key} className="bg-white p-6 rounded-xl border border-gray-200 flex gap-6">
                  <img
                    src={item.image || item.image_url || item.img || '/images/no-image.png'}
                    alt={item.name}
                    className="w-24 h-24 object-cover rounded-lg bg-gray-100"
                    onError={(e) => {
                      e.target.onerror = null
                      e.target.src = '/images/no-image.png'
                    }}
                  />
                  
                  <div className="flex-1">
                    <div className="flex justify-between items-start mb-2">
                      <div>
                        <h3 className="font-semibold text-lg text-gray-900">{item.name}</h3>
                        <p className="text-sm text-gray-500">
                          {item.category} {item.brand && `· ${item.brand}`}
                        </p>
                        {item.selectedSize && (
                          <p className="text-sm text-gray-500 mt-1">Size: {item.selectedSize}</p>
                        )}
                      </div>
                      <button
                        onClick={() => removeFromCart(item.key)}
                        className="text-gray-400 hover:text-red-600 transition-colors"
                      >
                        <Trash2 size={20} />
                      </button>
                    </div>

                    <div className="flex items-center justify-between mt-4">
                      <div className="flex items-center gap-3">
                        <button
                          onClick={() => updateQty(item.key, Math.max(1, qty - 1))}
                          className="w-8 h-8 flex items-center justify-center bg-white border border-gray-300 rounded-lg text-gray-900 hover:bg-gray-50 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                          disabled={qty <= 1}
                        >
                          <Minus size={16} />
                        </button>
                        <span className="w-8 text-center font-medium text-gray-900">{qty}</span>
                        <button
                          onClick={() => updateQty(item.key, qty + 1)}
                          className="w-8 h-8 flex items-center justify-center bg-white border border-gray-300 rounded-lg text-gray-900 hover:bg-gray-50 transition-colors"
                        >
                          <Plus size={16} />
                        </button>
                      </div>

                      <div className="text-right">
                        <p className="text-lg font-bold text-gray-900">
                          KSh {itemTotal.toLocaleString()}
                        </p>
                        <p className="text-sm text-gray-500">
                          KSh {price.toLocaleString()} each
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
              )
            })}
          </div>

          {/* Order Summary */}
          <div className="lg:col-span-1">
            <div className="bg-white p-6 rounded-xl border border-gray-200 h-fit sticky top-24">
              <h2 className="text-xl font-bold text-gray-900 mb-4">Order Summary</h2>
              
              <div className="space-y-3 text-sm mb-6">
                <div className="flex justify-between text-gray-600">
                  <span>Subtotal ({itemCount} {itemCount === 1 ? 'item' : 'items'})</span>
                  <span className="font-medium text-gray-900">KSh {total.toLocaleString()}</span>
                </div>
                <div className="flex justify-between text-gray-600">
                  <span>Shipping</span>
                  <span className="text-green-600 font-medium">Free</span>
                </div>
                <div className="flex justify-between text-gray-600">
                  <span>Tax</span>
                  <span>Calculated at checkout</span>
                </div>
              </div>

              <div className="flex justify-between text-xl font-bold my-6 pt-4 border-t border-gray-200 text-gray-900">
                <span>Total</span>
                <span>KSh {total.toLocaleString()}</span>
              </div>

              <button
                onClick={handleCheckout}
                className="w-full py-3 bg-gray-900 text-white rounded-lg hover:bg-black transition font-semibold active:scale-[0.98]"
              >
                Proceed to Checkout
              </button>

              <Link
                to="/"
                className="block text-center mt-4 text-sm text-gray-600 hover:text-gray-900 transition-colors"
              >
                Continue Shopping
              </Link>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}