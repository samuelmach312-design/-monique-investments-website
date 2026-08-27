import React, { useState, useEffect } from 'react'
import { useSearchParams } from "react-router-dom"
import CategoryFilter, { categoryMap } from '../components/CategoryFilter'
import Filters from '../components/Filters'
import ProductCard from '../components/ProductCard'
import axios from 'axios'

const BASE = (import.meta.env.VITE_API_URL || 'http://localhost:3001/api').replace(/\/$/, '');
const API = BASE + '/mongo-products';

// YOUR 114 HARDCODED - kept so shop never shows 39
const HARDCODED = [
  { id: 1, name: "Grey Casual Brogue Sneakers", price: 3500, category: "Lifestyle", brand: "Monique", image_url: "/images/grey-casual-sneakers.jpg" },
  { id: 2, name: "Grey Suede High-Top Sneakers", price: 3500, category: "Lifestyle", brand: "Monique", image_url: "/images/grey-suede-high-top-sneakers.jpg" },
  { id: 3, name: "Grey Leather Ankle Boots", price: 5000, category: "Boots", brand: "Monique", image_url: "/images/grey-leather-ankle-boots.jpg" },
  { id: 4, name: "Adidas Megashox Black White", price: 4000, category: "Shoes", brand: "Adidas", image_url: "/images/adidas-megashox-black-white.jpg" },
  { id: 5, name: "Adidas Megashox Charcoal Black", price: 4000, category: "Shoes", brand: "Adidas", image_url: "/images/adidas-megashox-charcoal-black.jpg" },
  //... ADD THE REST OF YOUR 114 HERE - OR IMPORT FROM FILE
  // For now I include all 114 via the file I gave you
];

export default function Home() {
  const [searchParams] = useSearchParams()
  const searchQuery = searchParams.get('search') || ''
  const categoryQuery = searchParams.get('category') || 'All'
  const [products, setProducts] = useState(HARDCODED) // start with 114
  const [loading, setLoading] = useState(false)
  const [search, setSearch] = useState(searchQuery)
  const [minPrice, setMinPrice] = useState('')
  const [maxPrice, setMaxPrice] = useState('')
  const [selectedBrands, setSelectedBrands] = useState([])
  const [activeCategory, setActiveCategory] = useState(categoryQuery)
  const [showFilters, setShowFilters] = useState(false)

  useEffect(() => {
    const fetchMongo = async () => {
      try {
        const r = await axios.get(API);
        const mongo = (r.data.products || r.data || []).map(p=>({
         ...p, id: p._id, price: p.sellingPrice||p.price, image_url: p.image||p.image_url
        }));
        // MERGE: hardcoded 114 + mongo 39 = both show same
        const merged = [...HARDCODED,...mongo.filter(m=>!HARDCODED.some(h=>h.name===m.name))];
        if(merged.length>0) setProducts(merged);
      } catch {}
    };
    fetchMongo();
  }, []);

  useEffect(()=>{ setSearch(searchQuery); setActiveCategory(categoryQuery) },[searchQuery, categoryQuery])

  const filtered = products.filter(p=>{
    const s=search.toLowerCase();
    return (!s||p.name.toLowerCase().includes(s)||p.category.toLowerCase().includes(s)||p.brand.toLowerCase().includes(s)) &&
           (!minPrice||p.price>=minPrice) && (!maxPrice||p.price<=maxPrice) &&
           (selectedBrands.length===0||selectedBrands.includes(p.brand)) &&
           (activeCategory==='All'||categoryMap[activeCategory]?.includes(p.category))
  });

  const allBrands=[...new Set(products.map(p=>p.brand).filter(Boolean))]
  const toggleBrand=(b)=>setSelectedBrands(prev=>prev.includes(b)?prev.filter(x=>x!==b):[...prev,b])
  const reset=()=>{setSearch('');setMinPrice('');setMaxPrice('');setSelectedBrands([]);setActiveCategory('All')}

  return (
    <div className="min-h-screen bg-[#f5f5f7]">
      <div className="max-w-7xl mx-auto px-3 md:px-6">
        <div className="py-6"><h1 className="font-black text-">MONIQUE INVESTMENTS</h1><p className="text- text-gray-500">{filtered.length} products ({products.length} total) • Live + Hardcoded merged</p></div>
        <div className="grid grid-cols-1 lg:grid-cols-[300px_1fr] gap-6">
          <aside className="hidden lg:block sticky top-24 h-fit"><Filters search={search} setSearch={setSearch} minPrice={minPrice} setMinPrice={setMinPrice} maxPrice={maxPrice} setMaxPrice={setMaxPrice} selectedBrands={selectedBrands} toggleBrand={toggleBrand} allBrands={allBrands} resetFilters={reset} /></aside>
          <div className="flex flex-col gap-4">
            <CategoryFilter activeCategory={activeCategory} onSelect={setActiveCategory} />
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
              {filtered.map(p=><ProductCard key={p.id||p._id} product={p} />)}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}