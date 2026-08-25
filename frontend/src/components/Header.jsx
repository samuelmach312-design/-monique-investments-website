import React, { useState, useEffect, useRef } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useCart } from '../context/CartContext'
import { useAuth } from '../context/AuthContext'
import { ShoppingCart, Menu, X, Search, Download } from 'lucide-react'

export default function Header() {
  const [deferredPrompt, setDeferredPrompt] = useState(null)

  useEffect(() => {
     const handler = (e) => {
      e.preventDefault()
      setDeferredPrompt(e)
    }
    window.addEventListener('beforeinstallprompt', handler)
    return () => window.removeEventListener('beforeinstallprompt', handler)
  }, [])

  const handleInstallClick = async () => {
    if (!deferredPrompt) return
    deferredPrompt.prompt()
    const { outcome } = await deferredPrompt.userChoice
    if (outcome === 'accepted') {
      setDeferredPrompt(null)
    }
  }

  const { cart } = useCart()
  const { user, logout } = useAuth()
  const [search, setSearch] = useState('')
  const [showDropdown, setShowDropdown] = useState(false)
  const [filteredProducts, setFilteredProducts] = useState([])
  const [mobileMenu, setMobileMenu] = useState(false)
  const [allProducts, setAllProducts] = useState([])
  const navigate = useNavigate()
  const searchRef = useRef(null)

  const totalItems = cart.reduce((sum, item) => sum + (item.qty || 0), 0)

  useEffect(() => {
    const mockProducts = [
      { id: 1, name: "Grey Casual Brogue Sneakers", price: 4000, image_url: "/images/grey-casual-sneakers.jpg", category: "Lifestyle" },
      { id: 4, name: "Adidas Megashox Black White", price: 5500, image_url: "/images/adidas-megashox-black-white.jpg", category: "Shoes" },
      { id: 16, name: "Nike Air Force 1 White", price: 6500, image_url: "/images/nike-air-force-1-white.jpg", category: "Shoes" },
      { id: 19, name: "Work Boots Brown Cat", price: 5800, image_url: "/images/work-boots-brown-cat.jpg", category: "Boots" },
      { id: 29, name: "Braided Belt Brown", price: 1800, image_url: "/images/braided-belt-brown.jpg", category: "Accessories" }
    ]
    setAllProducts(mockProducts)
  }, [])

  useEffect(() => {
    if (search.trim().length > 0) {
      const searchLower = search.toLowerCase().trim()
      const results = allProducts.filter(product =>
        product.name?.toLowerCase().includes(searchLower) ||
        product.brand?.toLowerCase().includes(searchLower) ||
        product.category?.toLowerCase().includes(searchLower) ||
        product.description?.toLowerCase().includes(searchLower)
      ).slice(0, 5)
      setFilteredProducts(results)
      setShowDropdown(true)
    } else {
      setFilteredProducts([])
      setShowDropdown(false)
    }
  }, [search, allProducts])

  useEffect(() => {
    const handleClickOutside = (e) => {
      if (searchRef.current &&!searchRef.current.contains(e.target)) {
        setShowDropdown(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  const handleSearch = (e) => {
    e.preventDefault()
    if (search.trim()) {
      navigate(`/?search=${encodeURIComponent(search)}`)
      setSearch('')
      setShowDropdown(false)
      setMobileMenu(false)
    }
  }

  const handleSelectProduct = (product) => {
    navigate(`/?search=${encodeURIComponent(product.name)}`)
    setSearch('')
    setShowDropdown(false)
    setMobileMenu(false)
  }

  const handleLogout = () => {
    logout()
    navigate('/')
    setMobileMenu(false)
  }

  return (
    <>
      <header className="sticky top-0 z-50 bg-white/95 backdrop-blur-xl border-b border-gray-200">
        <div className="max-w-7xl mx-auto px-3 md:px-6 lg:px-8">
          <div className="flex items-center justify-between gap-4 h-14 md:h-16">
            <Link to="/" className="flex items-center gap-2 md:gap-3 group shrink-0">
              <img src="/images/monique-logo.png" alt="Monique" className="h-8 md:h-10 w-auto object-contain group-hover:scale-105 transition-transform" onError={(e) => { e.target.style.display = 'none' }} />
              <div className="hidden sm:block">
                <div className="text-gray-900 font-black text-base md:text-lg leading-none tracking-wide">MONIQUE</div>
                <div className="text-[#3b82f6] text- md:text-xs uppercase tracking-[0.18em] font-bold">INVESTMENTS</div>
              </div>
            </Link>

            <form onSubmit={handleSearch} className="hidden md:flex flex-1 max-w-lg mx-4 lg:mx-8" ref={searchRef}>
              <div className="relative w-full">
                <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
                <input type="text" value={search} onChange={(e) => setSearch(e.target.value)} onFocus={() => search && setShowDropdown(true)} placeholder="Search products..." className="w-full pl-10 pr-4 py-2.5 bg-gray-50 border border-gray-200 rounded-full text-sm font-medium text-gray-900 placeholder:text-gray-500 focus:outline-none focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-50 transition-all" />
                {showDropdown && filteredProducts.length > 0 && (
                  <div className="absolute top-full left-0 right-0 mt-2 bg-white border border-gray-200 rounded-2xl shadow-xl overflow-hidden z-50">
                    {filteredProducts.map((product) => (
                      <button key={product.id} type="button" onClick={() => handleSelectProduct(product)} className="w-full flex items-center gap-3 px-4 py-3 hover:bg-gray-50 text-left border-b border-gray-100 last:border-0">
                        <img src={product.image_url} alt={product.name} className="w-12 h-12 object-cover rounded-xl bg-gray-100 shrink-0" onError={(e) => { e.target.src = 'https://via.placeholder.com/48/f3f4f6/9ca3af?text=No+Img' }} />
                        <div className="flex-1 min-w-0">
                          <p className="text-sm font-semibold text-gray-900 truncate">{product.name}</p>
                          <p className="text-xs text-gray-500">KSh {product.price?.toLocaleString()}</p>
                        </div>
                      </button>
                    ))}
                    <button type="submit" className="w-full px-4 py-3 text-sm font-bold text-blue-600 hover:bg-blue-50 transition-colors border-t border-gray-200">See all results for "{search}"</button>
                  </div>
                )}
              </div>
            </form>

            <div className="hidden md:flex items-center gap-3 shrink-0">
              <Link to="/" className="px-3 py-2 text-sm font-bold text-gray-600 hover:text-gray-900">Home</Link>
              {user && <span className="text-sm text-gray-500 hidden lg:block">Hi, <b className="text-gray-900">{user.name || user.email?.split('@')[0]}</b></span>}
              <Link to="/cart" className="relative flex items-center gap-2 px-4 py-2.5 bg-[#0f172a] text-white rounded-full text-sm font-bold hover:bg-black transition-all">
                <ShoppingCart size={16} /> Cart
                {totalItems > 0 && <span className="bg-blue-600 text-white text- min-w- h-5 rounded-full flex items-center justify-center px-1">{totalItems > 99? '99+' : totalItems}</span>}
              </Link>
              {user? (<button onClick={handleLogout} className="text-sm font-medium text-gray-500 hover:text-red-600">Logout</button>) : (<Link to="/login" className="px-4 py-2 bg-gray-900 text-white text-sm font-bold rounded-full hover:bg-black">Login</Link>)}

              {deferredPrompt && (
                <button onClick={handleInstallClick} className="flex items-center gap-2 px-4 py-2.5 bg-blue-600 text-white rounded-full text-sm font-bold hover:bg-blue-700 transition-all">
                  <Download size={16} /> Install
                </button>
              )}
            </div>

            <button onClick={() => setMobileMenu(true)} className="md:hidden w-10 h-10 rounded-full bg-[#0f172a] text-white flex items-center justify-center hover:bg-black transition-colors">
              <Menu size={20} />
            </button>
          </div>
        </div>
      </header>

      {mobileMenu && (
        <div className="fixed inset-0 z-[100] md:hidden">
          <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" onClick={() => setMobileMenu(false)}></div>
          <div className="absolute right-0 top-0 h-full w-[86%] max-w- bg-white shadow-2xl flex flex-col">
            <div className="p-5 flex items-center justify-between bg-gradient-to-br from-[#0f172a] to-[#1e293b] text-white">
              <div className="flex flex-col leading-none">
                <span className="text- font-black tracking-wide">MONIQUE</span>
                <span className="text- font-bold tracking-[0.2em] text-blue-400">INVESTMENTS</span>
              </div>
              <button onClick={() => setMobileMenu(false)} className="w-9 h-9 rounded-full bg-white/10 flex items-center justify-center hover:bg-white/20 transition-colors"><X size={18} /></button>
            </div>

            <form onSubmit={handleSearch} className="p-4 border-b border-gray-100">
              <div className="relative">
                <Search className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
                <input type="text" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search products..." className="w-full pl-10 pr-4 py-3.5 bg-gray-50 border border-gray-200 rounded-2xl text-sm font-medium focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-50 outline-none transition-all" />
              </div>
              {showDropdown && filteredProducts.length > 0 && (
                <div className="mt-3 bg-white border border-gray-200 rounded-2xl shadow-lg overflow-hidden max-h-60 overflow-y-auto">
                  {filteredProducts.map((product) => (
                    <button key={product.id} type="button" onClick={() => handleSelectProduct(product)} className="w-full flex items-center gap-3 px-4 py-3 hover:bg-gray-50 text-left border-b border-gray-50 last:border-0">
                      <img src={product.image_url} alt={product.name} className="w-10 h-10 object-cover rounded-xl bg-gray-100 shrink-0" />
                      <div className="flex-1 min-w-0"><p className="text-sm font-semibold truncate">{product.name}</p><p className="text-xs text-gray-500">KSh {product.price?.toLocaleString()}</p></div>
                    </button>
                  ))}
                </div>
              )}
            </form>

            <div className="flex-1 p-3 space-y-2.5 overflow-y-auto">
              <Link to="/" onClick={() => setMobileMenu(false)} className="flex items-center gap-3 px-4 py-3.5 rounded-2xl bg-[#0f172a] text-white font-bold text-sm shadow-lg"><span className="w-9 h-9 rounded-full bg-white/10 flex items-center justify-center text-sm">⌂</span>Home<span className="ml-auto w-2 h-2 bg-blue-400 rounded-full animate-pulse"></span></Link>

              <Link to="/cart" onClick={() => setMobileMenu(false)} className="flex items-center gap-3 px-4 py-3.5 rounded-2xl bg-white border border-gray-200 text-gray-900 font-bold text-sm hover:border-gray-300 hover:bg-gray-50 transition-colors"><span className="w-9 h-9 rounded-full bg-gray-50 flex items-center justify-center"><ShoppingCart size={16} /></span>Cart{totalItems > 0 && <span className="ml-auto bg-blue-600 text-white text-xs px-2.5 py-1 rounded-full font-bold">{totalItems}</span>}</Link>

              {deferredPrompt && (
                <button onClick={() => { handleInstallClick(); setMobileMenu(false); }} className="w-full flex items-center gap-3 px-4 py-3.5 rounded-2xl bg-blue-600 text-white font-bold text-sm shadow-lg hover:bg-blue-700 transition-colors">
                  <span className="w-9 h-9 rounded-full bg-white/20 flex items-center justify-center"><Download size={16} /></span>
                  Install App
                  <span className="ml-auto text-xs bg-white/20 px-2 py-1 rounded-full">FREE</span>
                </button>
              )}

              {user && (
                <div className="mt-5 p-4 rounded-2xl bg-blue-50 border border-blue-100">
                  <p className="text- font-bold text-blue-600 uppercase tracking-widest mb-2">Account</p>
                  <div className="flex items-center gap-3">
                    <span className="w-10 h-10 rounded-full bg-blue-600 text-white flex items-center justify-center font-bold">{(user.name || user.email || 'U')[0].toUpperCase()}</span>
                    <div><p className="text-sm font-bold text-gray-900">{user.name || user.email?.split('@')[0]}</p><p className="text-xs text-gray-500 truncate max-w-">{user.email}</p></div>
                  </div>
                </div>
              )}
            </div>

            <div className="p-3 border-t border-gray-100 bg-gray-50/50">
              {user? (<button onClick={handleLogout} className="w-full flex items-center gap-3 px-4 py-3.5 rounded-2xl bg-white border border-red-100 text-red-600 font-bold text-sm hover:bg-red-50 transition-colors"><span className="w-9 h-9 rounded-full bg-red-50 flex items-center justify-center">↪</span> Logout</button>) : (<div className="grid grid-cols-2 gap-2"><Link to="/login" onClick={() => setMobileMenu(false)} className="py-3.5 rounded-2xl bg-white border border-gray-200 text-center font-bold text-sm">Login</Link><Link to="/signup" onClick={() => setMobileMenu(false)} className="py-3.5 rounded-2xl bg-[#0f172a] text-white text-center font-bold text-sm">Sign Up</Link></div>)}
              <p className="text- text-center text-gray-400 mt-3 font-medium">© 2025 Monique Investments</p>
            </div>
          </div>
        </div>
      )}
    </>
  )
}