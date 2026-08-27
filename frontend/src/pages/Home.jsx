import React, { useState, useEffect } from 'react'
import { useCart } from '../context/CartContext'
import { useSearchParams } from "react-router-dom"
import CategoryFilter, { categoryMap } from '../components/CategoryFilter'
import Filters from '../components/Filters'
import ProductCard from '../components/ProductCard'
import axios from 'axios'

const BASE = (import.meta.env.VITE_API_URL || 'http://localhost:3001/api').replace(/\/$/, '');
const API = BASE + '/mongo-products';

export default function Home() {
  const [searchParams] = useSearchParams()
  const searchQuery = searchParams.get('search') || ''
  const categoryQuery = searchParams.get('category') || 'All'
  const [products, setProducts] = useState([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState(searchQuery)
  const [minPrice, setMinPrice] = useState('')
  const [maxPrice, setMaxPrice] = useState('')
  const [selectedBrands, setSelectedBrands] = useState([])
  const [activeCategory, setActiveCategory] = useState(categoryQuery)
  const [showFilters, setShowFilters] = useState(false)
  const { addToCart } = useCart()

  useEffect(() => {
    const fetchProducts = async () => {
      try {
        const r = await axios.get(API);
        const data = r.data.products || r.data || [];
        // Normalize image field
        const normalized = data.map(p => ({
         ...p,
          id: p._id,
          price: p.sellingPrice || p.price,
          image_url: p.image || p.image_url,
          brand: p.brand || 'Monique',
          category: p.category || 'Shoes'
        }));
        setProducts(normalized);
      } catch (err) {
        console.log('API offline', err.message)
      } finally { setLoading(false) }
    }
    fetchProducts()
  }, [])

  useEffect(() => { setSearch(searchQuery); setActiveCategory(categoryQuery) }, [searchQuery, categoryQuery])

  const filteredProducts = products.filter(product => {
    const s = search.toLowerCase().trim()
    const matchesSearch =!s || product.name?.toLowerCase().includes(s) || product.category?.toLowerCase().includes(s) || product.brand?.toLowerCase().includes(s)
    const matchesPrice = (!minPrice || Number(product.price) >= Number(minPrice)) && (!maxPrice || Number(product.price) <= Number(maxPrice))
    const matchesBrand = selectedBrands.length === 0 || selectedBrands.includes(product.brand)
    const allowed = categoryMap[activeCategory]
    const matchesCategory = activeCategory === 'All' || (allowed && allowed.includes(product.category))
    return matchesSearch && matchesPrice && matchesBrand && matchesCategory
  })

  const allBrands = [...new Set(products.map(p => p.brand).filter(Boolean))]
  const toggleBrand = (brand) => setSelectedBrands(prev => prev.includes(brand)? prev.filter(b => b!== brand) : [...prev, brand])
  const resetFilters = () => { setSearch(''); setMinPrice(''); setMaxPrice(''); setSelectedBrands([]); setActiveCategory('All') }

  if (loading) return (<div className="min-h-screen bg-[#f5f5f7] flex items-center justify-center"><div className="text-gray-500">Loading vault...</div></div>)

  return (
    <div className="min-h-screen bg-[#f5f5f7] w-full overflow-x-hidden">
      <div className="w-full max-w-7xl mx-auto px-3 md:px-6">
        <div className="py-6">
          <h1 className="font-black text-2xl">Monique Investments</h1>
          <div className="flex items-center gap-3 mt-1"><h2 className="font-bold">{activeCategory}</h2><span className="text-sm text-gray-500">{filteredProducts.length} products ({products.length} total) • Live synced with Admin</span></div>
        </div>
        <div className="grid grid-cols-1 lg:grid-cols-[300px_1fr] gap-6">
          <aside className="hidden lg:block h-fit sticky top-24"><Filters search={search} setSearch={setSearch} minPrice={minPrice} setMinPrice={setMinPrice} maxPrice={maxPrice} setMaxPrice={setMaxPrice} selectedBrands={selectedBrands} toggleBrand={toggleBrand} allBrands={allBrands} resetFilters={resetFilters} /></aside>
          <div className="flex flex-col gap-4">
            <div className="flex items-center justify-end lg:hidden"><button onClick={() => setShowFilters(true)} className="px-4 py-2.5 bg-white border rounded-full text-sm font-bold">Filters</button></div>
            <CategoryFilter activeCategory={activeCategory} onSelect={setActiveCategory} />
            <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-3 gap-3 md:gap-5">
              {filteredProducts.length === 0? (<div className="col-span-full text-center py-16"><p>No products found</p><button onClick={resetFilters} className="mt-3 text-blue-600 font-bold">Clear filters</button></div>) : filteredProducts.map(product => (<ProductCard key={product.id || product._id} product={product} />))}
            </div>
          </div>
        </div>
      </div>
      {showFilters && (<div className="lg:hidden fixed inset-0 z-50 bg-black/30" onClick={() => setShowFilters(false)}><div className="absolute right-0 top-0 h-full w-full max-w-sm p-4" onClick={e => e.stopPropagation()}><Filters search={search} setSearch={setSearch} minPrice={minPrice} setMinPrice={setMinPrice} maxPrice={maxPrice} setMaxPrice={setMaxPrice} selectedBrands={selectedBrands} toggleBrand={toggleBrand} allBrands={allBrands} resetFilters={resetFilters} onClose={() => setShowFilters(false)} /></div></div>)}
    </div>
  )
}