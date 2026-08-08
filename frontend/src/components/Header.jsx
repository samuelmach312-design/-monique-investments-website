import React, { useState, useEffect, useRef } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useCart } from '../context/CartContext'
import { useAuth } from '../context/AuthContext'
import { ShoppingCart, Menu, X, Search } from 'lucide-react'

export default function Header() {
  const { cart } = useCart()
  const { user, logout } = useAuth()
  const [search, setSearch] = useState('')
  const [showDropdown, setShowDropdown] = useState(false)
  const [filteredProducts, setFilteredProducts] = useState([])
  const [mobileMenu, setMobileMenu] = useState(false)
  const [allProducts, setAllProducts] = useState([])
  const navigate = useNavigate()
  const searchRef = useRef(null)

  // FIX: Your cart uses 'qty' not 'quantity'
  const totalItems = cart.reduce((sum, item) => sum + (item.qty || 0), 0)

  // Load products for search dropdown - replace with your API later
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
    <header className="sticky top-0 z-50 bg-white/95 backdrop-blur-xl border-b border-gray-200">
      <div className="max-w-7xl mx-auto px-3 md:px-6 lg:px-8">
        <div className="flex items-center justify-between gap-4 h-14 md:h-16">

          {/* Logo */}
          <Link to="/" className="flex items-center gap-2 md:gap-3 group shrink-0">
            <img
              src="/images/monique-logo.png"
              alt="Monique"
              className="h-8 md:h-10 w-auto object-contain group-hover:scale-105 transition-transform"
              onError={(e) => { e.target.style.display = 'none' }}
            />
            <div className="hidden sm:block">
              <div className="text-gray-900 font-bold text-base md:text-lg leading-none tracking-wide">
                MONIQUE
              </div>
              <div className="text-[#D4AF37] text-[10px] md:text-xs uppercase tracking-[0.15em] font-semibold">
                INVESTMENTS
              </div>
            </div>
          </Link>

          {/* Search - Desktop */}
          <form onSubmit={handleSearch} className="hidden md:flex flex-1 max-w-lg mx-4 lg:mx-8" ref={searchRef}>
            <div className="relative w-full">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                onFocus={() => search && setShowDropdown(true)}
                placeholder="Search products..."
                className="w-full pl-10 pr-4 py-2.5 bg-gray-50 border border-gray-200 rounded-lg text-sm text-gray-900 placeholder:text-gray-500 focus:outline-none focus:ring-2 focus:ring-[#D4AF37]/50 focus:border-[#D4AF37] transition-all"
              />

              {showDropdown && filteredProducts.length > 0 && (
                <div className="absolute top-full left-0 right-0 mt-2 bg-white border border-gray-200 rounded-xl shadow-xl overflow-hidden z-50">
                  {filteredProducts.map((product) => (
                    <button
                      key={product.id}
                      type="button"
                      onClick={() => handleSelectProduct(product)}
                      className="w-full flex items-center gap-3 px-4 py-3 hover:bg-gray-50 transition-colors text-left border-b border-gray-100 last:border-0"
                    >
                      <img
                        src={product.image_url}
                        alt={product.name}
                        className="w-12 h-12 object-cover rounded-lg bg-gray-100 shrink-0"
                        onError={(e) => { 
                          e.target.src = 'https://via.placeholder.com/48/f3f4f6/9ca3af?text=No+Img'
                        }}
                      />
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-gray-900 truncate">
                          {product.name}
                        </p>
                        <p className="text-xs text-gray-500">
                          KSh {product.price?.toLocaleString()}
                        </p>
                      </div>
                    </button>
                  ))}
                  {search && (
                    <button
                      type="submit"
                      className="w-full px-4 py-3 text-sm font-semibold text-[#D4AF37] hover:bg-gray-50 transition-colors border-t border-gray-200"
                    >
                      See all results for "{search}"
                    </button>
                  )}
                </div>
              )}

              {showDropdown && search && filteredProducts.length === 0 && (
                <div className="absolute top-full left-0 right-0 mt-2 bg-white border border-gray-200 rounded-xl shadow-xl p-4 z-50">
                  <p className="text-sm text-gray-500 text-center">
                    No products found for "{search}"
                  </p>
                </div>
              )}
            </div>
          </form>

          {/* Actions - Desktop */}
          <div className="hidden md:flex items-center gap-3 lg:gap-5 shrink-0">
            <Link
              to="/"
              className="px-2 py-2 text-sm font-medium text-gray-600 hover:text-gray-900 transition-colors"
            >
              Home
            </Link>

            {user? (
              <div className="flex items-center gap-3 lg:gap-5">
                <span className="text-sm text-gray-600 hidden lg:block">
                  Hi, <span className="text-gray-900 font-medium">{user.name || user.email?.split('@')[0]}</span>
                </span>
                <button
                  onClick={handleLogout}
                  className="text-sm font-medium text-gray-600 hover:text-gray-900 transition-colors"
                >
                  Logout
                </button>
              </div>
            ) : (
              <div className="flex items-center gap-3">
                <Link
                  to="/login"
                  className="text-sm font-medium text-gray-600 hover:text-gray-900 transition-colors"
                >
                  Login
                </Link>
                <Link
                  to="/signup"
                  className="px-4 py-2 bg-gray-900 text-white text-sm font-medium rounded-lg hover:bg-black transition-colors"
                >
                  Sign Up
                </Link>
              </div>
            )}

            <Link to="/cart" className="relative">
              <div className="flex items-center gap-2 px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg hover:border-gray-300 hover:bg-gray-100 transition-all">
                <ShoppingCart size={20} className="text-gray-900" />
                <span className="hidden lg:block text-sm font-medium text-gray-900">Cart</span>
              </div>
              {totalItems > 0 && (
                <span className="absolute -top-2 -right-2 min-w-5 h-5 bg-[#D4AF37] text-white text-xs font-bold rounded-full flex items-center justify-center px-1.5">
                  {totalItems > 99? '99+' : totalItems}
                </span>
              )}
            </Link>
          </div>

          {/* Mobile Menu Button */}
          <button
            onClick={() => setMobileMenu(!mobileMenu)}
            className="md:hidden p-2 bg-gray-50 border border-gray-200 rounded-lg text-gray-900 hover:bg-gray-100 transition-colors"
          >
            {mobileMenu? <X size={20} /> : <Menu size={20} />}
          </button>
        </div>
      </div>

      {/* Mobile Menu */}
      {mobileMenu && (
        <div className="md:hidden border-t border-gray-200 bg-white">
          <div className="p-4 space-y-3">
            <form onSubmit={handleSearch} className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
              <input
                type="text"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search products..."
                className="w-full pl-10 pr-4 py-2.5 bg-gray-50 border border-gray-200 rounded-lg text-sm text-gray-900 placeholder:text-gray-500 focus:border-[#D4AF37] focus:ring-1 focus:ring-[#D4AF37]/50 outline-none transition-all"
              />
              {showDropdown && filteredProducts.length > 0 && (
                <div className="absolute top-full left-0 right-0 mt-2 bg-white border border-gray-200 rounded-xl shadow-xl overflow-hidden z-50 max-h-80 overflow-y-auto">
                  {filteredProducts.map((product) => (
                    <button
                      key={product.id}
                      type="button"
                      onClick={() => handleSelectProduct(product)}
                      className="w-full flex items-center gap-3 px-4 py-3 hover:bg-gray-50 transition-colors text-left border-b border-gray-100 last:border-0"
                    >
                      <img
                        src={product.image_url}
                        alt={product.name}
                        className="w-10 h-10 object-cover rounded-lg bg-gray-100 shrink-0"
                        onError={(e) => { 
                          e.target.src = 'https://via.placeholder.com/40/f3f4f6/9ca3af?text=N/A'
                        }}
                      />
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-gray-900 truncate">
                          {product.name}
                        </p>
                        <p className="text-xs text-gray-500">
                          KSh {product.price?.toLocaleString()}
                        </p>
                      </div>
                    </button>
                  ))}
                </div>
              )}
            </form>

            <Link
              to="/"
              onClick={() => setMobileMenu(false)}
              className="block px-4 py-2.5 bg-gray-50 border border-gray-200 rounded-lg text-sm font-medium text-gray-900 hover:bg-gray-100 transition-colors"
            >
              Home
            </Link>

            <Link
              to="/cart"
              onClick={() => setMobileMenu(false)}
              className="flex items-center justify-between px-4 py-2.5 bg-gray-50 border border-gray-200 rounded-lg text-sm font-medium text-gray-900 hover:bg-gray-100 transition-colors"
            >
              <span>Cart</span>
              {totalItems > 0 && (
                <span className="px-2 py-0.5 bg-[#D4AF37] text-white text-xs font-bold rounded-full">
                  {totalItems > 99? '99+' : totalItems}
                </span>
              )}
            </Link>

            {user? (
              <>
                <div className="px-4 py-2.5 bg-gray-50 border border-gray-200 rounded-lg text-sm text-gray-600">
                  Hi, <span className="text-gray-900 font-medium">{user.name || user.email?.split('@')[0]}</span>
                </div>
                <button
                  onClick={handleLogout}
                  className="w-full px-4 py-2.5 bg-gray-50 border border-gray-200 rounded-lg text-sm font-medium text-gray-900 text-left hover:bg-gray-100 transition-colors"
                >
                  Logout
                </button>
              </>
            ) : (
              <>
                <Link
                  to="/login"
                  onClick={() => setMobileMenu(false)}
                  className="block px-4 py-2.5 bg-gray-50 border border-gray-200 rounded-lg text-sm font-medium text-gray-900 hover:bg-gray-100 transition-colors"
                >
                  Login
                </Link>
                <Link
                  to="/signup"
                  onClick={() => setMobileMenu(false)}
                  className="block px-4 py-2.5 bg-gray-900 text-white text-sm font-medium rounded-lg hover:bg-black transition-colors text-center"
                >
                  Sign Up
                </Link>
              </>
            )}
          </div>
        </div>
      )}
    </header>
  )
}

