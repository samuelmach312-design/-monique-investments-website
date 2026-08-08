import { useState } from 'react'
import { useCart } from '../context/CartContext'
import { useAuth } from '../context/AuthContext'
import { useNavigate, Link } from 'react-router-dom'
import { ArrowLeft, Loader2 } from 'lucide-react'

export default function Checkout() {
  const { cart = [], total, checkout } = useCart()
  const { user } = useAuth()
  const navigate = useNavigate()
  const [loading, setLoading] = useState(false)
  const [formData, setFormData] = useState({
    name: user?.name || '',
    phone: '',
    email: user?.email || '',
    address: '',
    city: 'Kangema',
    notes: ''
  })
  const [errors, setErrors] = useState({})

  const handleChange = (e) => {
    setFormData({...formData, [e.target.name]: e.target.value })
    setErrors({...errors, [e.target.name]: '' })
  }

  const validate = () => {
    const newErrors = {}
    if (!formData.name.trim()) newErrors.name = 'Name is required'
    if (!formData.phone.trim()) newErrors.phone = 'Phone is required'
    else if (!/^254\d{9}$/.test(formData.phone.replace(/\s/g, ''))) {
      newErrors.phone = 'Use format 254712345678'
    }
    if (!formData.email.trim()) newErrors.email = 'Email is required'
    if (!formData.address.trim()) newErrors.address = 'Address is required'
    if (!formData.city.trim()) newErrors.city = 'City is required'
    return newErrors
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    const newErrors = validate()
    if (Object.keys(newErrors).length > 0) return setErrors(newErrors)

    setLoading(true)
    try {
      const result = await checkout({
        customer: formData,
        phoneNumber: formData.phone.replace(/\s/g, '')
      })

      if (!result.success) {
        throw new Error(result.error || 'Order failed')
      }

      const orderData = {
        id: result.orderId,
        total: total,
        customer: formData,
        items: cart,
        timestamp: new Date().toISOString()
      }

      localStorage.setItem('lastOrder', JSON.stringify(orderData))

      // Send WhatsApp notification to you
      const itemList = cart.map(item => 
        `• ${item.name} x${item.qty}${item.selectedSize ? ` (${item.selectedSize})` : ''} - KSh ${(item.price * item.qty).toLocaleString()}`
      ).join('\n')

      fetch('/api/callmebot', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: `🛒 New Order #${result.orderId}\n\n👤 Customer: ${formData.name}\n📱 Phone: ${formData.phone}\n📧 Email: ${formData.email}\n\n📍 Delivery:\n${formData.address}, ${formData.city}\n\n💰 Total: KSh ${total.toLocaleString()}\n\n📦 Items:\n${itemList}\n\n📝 Notes: ${formData.notes || 'None'}\n\nPaybill: 507900\nAccount No: 2016253`
        })
      }).catch(err => console.error('WhatsApp notification failed:', err))

      navigate('/order-success')

    } catch (err) {
      console.error('Checkout error:', err)
      alert('Order failed: ' + err.message)
    } finally {
      setLoading(false)
    }
  }

  if (cart.length === 0) {
    return (
      <div className="min-h-screen bg-[#f5f5f7] flex items-center justify-center p-4">
        <div className="text-center">
          <h2 className="text-2xl font-bold text-gray-900 mb-4">Cart is empty</h2>
          <Link
            to="/"
            className="px-6 py-3 bg-gray-900 text-white rounded-lg hover:bg-black transition-colors inline-block"
          >
            Continue Shopping
          </Link>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-[#f5f5f7] p-4 md:p-8">
      <div className="max-w-6xl mx-auto">
        <button
          onClick={() => navigate('/cart')}
          className="flex items-center gap-2 text-gray-600 hover:text-gray-900 mb-6 transition-colors"
        >
          <ArrowLeft size={20} />
          Back to Cart
        </button>

        <div className="grid lg:grid-cols-[1fr_400px] gap-8">
          <div className="bg-white border border-gray-200 rounded-xl p-6">
            <h1 className="text-2xl font-bold text-gray-900 mb-6">Checkout</h1>

            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Full Name *</label>
                <input
                  type="text"
                  name="name"
                  value={formData.name}
                  onChange={handleChange}
                  className="w-full px-4 py-2.5 border border-gray-300 rounded-lg text-gray-900 placeholder:text-gray-400 focus:border-[#D4AF37] focus:ring-2 focus:ring-[#D4AF37]/50 outline-none transition-colors"
                  placeholder="John Doe"
                />
                {errors.name && <p className="text-red-500 text-xs mt-1">{errors.name}</p>}
              </div>

              <div className="grid sm:grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Phone *</label>
                  <input
                    type="tel"
                    name="phone"
                    value={formData.phone}
                    onChange={handleChange}
                    className="w-full px-4 py-2.5 border border-gray-300 rounded-lg text-gray-900 placeholder:text-gray-400 focus:border-[#D4AF37] focus:ring-2 focus:ring-[#D4AF37]/50 outline-none transition-colors"
                    placeholder="254712345678"
                  />
                  {errors.phone && <p className="text-red-500 text-xs mt-1">{errors.phone}</p>}
                </div>

                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-2">Email *</label>
                  <input
                    type="email"
                    name="email"
                    value={formData.email}
                    onChange={handleChange}
                    className="w-full px-4 py-2.5 border border-gray-300 rounded-lg text-gray-900 placeholder:text-gray-400 focus:border-[#D4AF37] focus:ring-2 focus:ring-[#D4AF37]/50 outline-none transition-colors"
                    placeholder="john@example.com"
                  />
                  {errors.email && <p className="text-red-500 text-xs mt-1">{errors.email}</p>}
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Address *</label>
                <input
                  type="text"
                  name="address"
                  value={formData.address}
                  onChange={handleChange}
                  className="w-full px-4 py-2.5 border border-gray-300 rounded-lg text-gray-900 placeholder:text-gray-400 focus:border-[#D4AF37] focus:ring-2 focus:ring-[#D4AF37]/50 outline-none transition-colors"
                  placeholder="123 Main St"
                />
                {errors.address && <p className="text-red-500 text-xs mt-1">{errors.address}</p>}
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">City *</label>
                <input
                  type="text"
                  name="city"
                  value={formData.city}
                  onChange={handleChange}
                  className="w-full px-4 py-2.5 border border-gray-300 rounded-lg text-gray-900 placeholder:text-gray-400 focus:border-[#D4AF37] focus:ring-2 focus:ring-[#D4AF37]/50 outline-none transition-colors"
                  placeholder="Nairobi"
                />
                {errors.city && <p className="text-red-500 text-xs mt-1">{errors.city}</p>}
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">Order Notes</label>
                <textarea
                  name="notes"
                  value={formData.notes}
                  onChange={handleChange}
                  rows={3}
                  className="w-full px-4 py-2.5 border border-gray-300 rounded-lg text-gray-900 placeholder:text-gray-400 focus:border-[#D4AF37] focus:ring-2 focus:ring-[#D4AF37]/50 outline-none transition-colors resize-none"
                  placeholder="Any special instructions..."
                />
              </div>

              <button
                type="submit"
                disabled={loading}
                className="w-full py-3 bg-gray-900 text-white font-semibold rounded-lg hover:bg-black transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
              >
                {loading && <Loader2 size={18} className="animate-spin" />}
                {loading ? 'Placing Order...' : `Place Order - KSh ${total.toLocaleString()}`}
              </button>
            </form>
          </div>

          <div className="bg-white border border-gray-200 rounded-xl p-6 h-fit lg:sticky lg:top-24">
            <h2 className="text-xl font-bold text-gray-900 mb-4">Order Summary</h2>

            <div className="space-y-3 mb-4 max-h-64 overflow-y-auto">
              {cart.map((item) => (
                <div key={item.key} className="flex gap-3 text-sm">
                  <img 
                    src={item.image_url || item.img || '/images/no-image.png'} 
                    alt={item.name} 
                    className="w-16 h-16 object-cover rounded-lg bg-gray-100" 
                  />
                  <div className="flex-1">
                    <div className="text-gray-900 font-medium">{item.name}</div>
                    <div className="text-gray-600">
                      Qty: {item.qty}
                      {item.selectedSize && ` · Size: ${item.selectedSize}`}
                    </div>
                  </div>
                  <div className="text-gray-900 font-semibold">
                    KSh {(item.price * item.qty).toLocaleString()}
                  </div>
                </div>
              ))}
            </div>

            <div className="border-t border-gray-200 pt-4 space-y-2">
              <div className="flex justify-between text-gray-600">
                <span>Subtotal</span>
                <span>KSh {total.toLocaleString()}</span>
              </div>
              <div className="flex justify-between text-gray-600">
                <span>Delivery</span>
                <span className="text-green-600 font-medium">Free</span>
              </div>
              <div className="flex justify-between text-gray-900 text-lg font-bold pt-2 border-t border-gray-200">
                <span>Total</span>
                <span>KSh {total.toLocaleString()}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
