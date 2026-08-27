import React, { useState, useEffect } from 'react'
import { useSearchParams } from "react-router-dom"
import CategoryFilter, { categoryMap } from '../components/CategoryFilter'
import Filters from '../components/Filters'
import ProductCard from '../components/ProductCard'

const HARDCODED_114 = [
  { id: 1, name: "Grey Casual Brogue Sneakers", price: 3500, category: "Lifestyle", brand: "Monique", image_url: "/images/grey-casual-sneakers.jpg" },
  { id: 2, name: "Grey Suede High-Top Sneakers", price: 3500, category: "Lifestyle", brand: "Monique", image_url: "/images/grey-suede-high-top-sneakers.jpg" },
  { id: 3, name: "Grey Leather Ankle Boots", price: 5000, category: "Boots", brand: "Monique", image_url: "/images/grey-leather-ankle-boots.jpg" },
  { id: 4, name: "Adidas Megashox Black White", price: 4000, category: "Shoes", brand: "Adidas", image_url: "/images/adidas-megashox-black-white.jpg" },
  { id: 5, name: "Adidas Megashox Charcoal Black", price: 4000, category: "Shoes", brand: "Adidas", image_url: "/images/adidas-megashox-charcoal-black.jpg" },
  { id: 6, name: "Black Leather Brogue Shoes", price: 5000, category: "Shoes", brand: "Monique", image_url: "/images/black-leather-brogue-shoes.jpg" },
  { id: 7, name: "Canvas Combat Boots Green", price: 3800, category: "Boots", brand: "Monique", image_url: "/images/canvas-combat-boots-green.jpg" },
  { id: 8, name: "Canvas Combat Boots Tan", price: 3800, category: "Boots", brand: "Monique", image_url: "/images/canvas-combat-boots-tan.jpg" },
  { id: 9, name: "Versace Style Sneaker Black Teal", price: 3500, category: "Lifestyle", brand: "Monique", image_url: "/images/versace-style-sneaker-black-teal.jpg" },
  { id: 10, name: "Delta Tactical Boots Tan", price: 5000, category: "Boots", brand: "Monique", image_url: "/images/delta-tactical-boots-tan.jpg" },
  { id: 11, name: "Designer Sneakers Navy", price: 3500, category: "Shoes", brand: "Monique", image_url: "/images/designer-sneakers-navy.jpg" },
  { id: 12, name: "Designer Sneakers White", price: 3500, category: "Shoes", brand: "Monique", image_url: "/images/designer-sneakers-white.jpg" },
  { id: 13, name: "Hiking Shoes AX4 Black", price: 3500, category: "Shoes", brand: "Monique", image_url: "/images/hiking-shoes-ax4-black.jpg" },
  { id: 14, name: "Hiking Shoes AX4 Grey", price: 3500, category: "Shoes", brand: "Monique", image_url: "/images/hiking-shoes-ax4-grey.jpg" },
  { id: 15, name: "Hiking Shoes AX4 Navy", price: 3500, category: "Shoes", brand: "Monique", image_url: "/images/hiking-shoes-ax4-navy.jpg" },
  { id: 16, name: "Nike Air Force 1 White", price: 2500, category: "Shoes", brand: "Nike", image_url: "/images/nike-air-force-1-white.jpg" },
  { id: 17, name: "Nike Air Max 90 Black Volt", price: 3500, category: "Shoes", brand: "Nike", image_url: "/images/nike-air-max-90-black-volt.jpg" },
  { id: 18, name: "Nike Air Max 90 Cordura Grey", price: 3500, category: "Shoes", brand: "Nike", image_url: "/images/nike-air-max-90-cordura-grey.jpg" },
  { id: 19, name: "Work Boots Brown Cat", price: 5000, category: "Boots", brand: "CAT", image_url: "/images/work-boots-brown-cat.jpg" },
  { id: 20, name: "Work Boots Grey Cat", price: 5000, category: "Boots", brand: "CAT", image_url: "/images/work-boots-grey-cat.jpg" },
  { id: 21, name: "Tactical Combat Boots Beige", price: 5000, category: "Boots", brand: "Monique", image_url: "/images/tactical-combat-boots-beige.jpg" },
  { id: 22, name: "Tan Leather Chukka Boots", price: 5000, category: "Boots", brand: "Monique", image_url: "/images/tan-leather-chukka-boots.jpg" },
  { id: 23, name: "Running Sneakers Grey Brown", price: 3000, category: "Shoes", brand: "Monique", image_url: "/images/running-sneakers-grey-brown.jpg" },
  { id: 24, name: "Versace Style Sneaker Black White", price: 3500, category: "Lifestyle", brand: "Monique", image_url: "/images/versace-style-sneaker-black-white.jpg" },
  { id: 25, name: "Motorsport Sneakers Black Red", price: 4000, category: "Lifestyle", brand: "Monique", image_url: "/images/motorsport-sneakers-black-red.jpg" },
  { id: 26, name: "Motorsport Sneakers Black White", price: 4000, category: "Lifestyle", brand: "Monique", image_url: "/images/motorsport-sneakers-black-white.jpg" },
  { id: 27, name: "Naked Wolfe Slider Black White", price: 3500, category: "Slides", brand: "Monique", image_url: "/images/naked-wolfe-slider-black-white.jpg" },
  { id: 28, name: "Naked Wolfe Slider Triple Black", price: 3500, category: "Slides", brand: "Monique", image_url: "/images/naked-wolfe-slider-triple-black.jpg" },
  { id: 29, name: "Braided Belt Brown", price: 800, category: "Accessories", brand: "Monique", image_url: "/images/braided-belt-brown.jpg" },
  { id: 30, name: "Canvas Belt Tan", price: 1000, category: "Accessories", brand: "Monique", image_url: "/images/canvas-belt-tan.jpg" },
  { id: 31, name: "Leather Belt Black", price: 1200, category: "Accessories", brand: "Monique", image_url: "/images/leather-belt-black.jpg" },
  { id: 32, name: "Elastic Shoe Laces", price: 200, category: "Accessories", brand: "Monique", image_url: "/images/elastic-shoe-laces.jpg" },
  { id: 33, name: "Jordan & Dunk Replacement Laces", price: 100, category: "Accessories", brand: "Monique", image_url: "/images/jordan-and-dunk-replacement-shoe-laces.jpg" },
  { id: 34, name: "Thick Rope Shoe Laces", price: 150, category: "Accessories", brand: "Monique", image_url: "/images/thick-rope-shoe-laces.jpg" },
  { id: 35, name: "Shoe Foam Cleaner", price: 400, category: "Shoe Care", brand: "Monique", image_url: "/images/shoe-foam-cleaner.jpg" },
  { id: 36, name: "Shoe Horn", price: 400, category: "Shoe Care", brand: "Monique", image_url: "/images/shoe-horn.jpg" },
  { id: 37, name: "Handtowels", price: 200, category: "Shoe Care", brand: "Monique", image_url: "/images/handtowels.jpg" },
  { id: 38, name: "Adidas Samba Black White", price: 3500, category: "Shoes", brand: "Adidas", image_url: "/images/samba.jpg" },
  { id: 39, name: "Nike Air Force 1 Undefeated Beige Navy", price: 3500, category: "Shoes", brand: "Nike", image_url: "/images/nike-af1-undefeated-beige.jpg" },
  { id: 40, name: "Nike Air Force 1 White Burgundy", price: 3500, category: "Shoes", brand: "Nike", image_url: "/images/nike-af1-white-burgundy.jpg" },
  { id: 41, name: "Nike Air Max 90 Surplus Grey", price: 3500, category: "Shoes", brand: "Nike", image_url: "/images/nike-air-max-90-grey-surplus.jpg" },
  { id: 42, name: "Jordan 1 Low Travis Olive Brown", price: 4000, category: "Shoes", brand: "Jordan", image_url: "/images/jordan-1-low-travis-olive.jpg" },
  { id: 43, name: "B Logo Black Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/b-logo-black.jpg" },
  { id: 44, name: "B Logo Dark Grey Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/b-logo-dark-grey.jpg" },
  { id: 45, name: "Black Floral Velvet Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/black-floral-velvet.jpg" },
  { id: 46, name: "Cream Zip Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/cream-zip.jpg" },
  { id: 47, name: "Black Oversized Hoodie", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/hoodie-black.jpg" },
  { id: 48, name: "Black Polo Shirt Triangle Logo", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-black-triangle.jpg" },
  { id: 49, name: "Sage Green Polo Triangle Logo", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-sage-triangle.jpg" },
  { id: 50, name: "Nike Air Max Plus TN Black Volt", price: 4000, category: "Shoes", brand: "Nike", image_url: "/images/nike-tn-black-volt.jpg" },
  { id: 51, name: "Nike Air Max Plus TN Black Blue", price: 4000, category: "Shoes", brand: "Nike", image_url: "/images/nike-tn-black-blue.jpg" },
  { id: 52, name: "Converse All Star Low Brown Leather", price: 3500, category: "Shoes", brand: "Converse", image_url: "/images/converse-low-brown-leather.jpg" },
  { id: 53, name: "Nike Air Force 1 Triple Black", price: 3500, category: "Shoes", brand: "Nike", image_url: "/images/nike-af1-triple-black.jpg" },
  { id: 54, name: "Converse Low Snakeskin Black", price: 2500, category: "Shoes", brand: "Converse", image_url: "/images/converse-low-snakeskin-black.jpg" },
  { id: 55, name: "Converse Low Snakeskin Maroon", price: 2500, category: "Shoes", brand: "Converse", image_url: "/images/converse-low-snakeskin-maroon.jpg" },
  { id: 56, name: "Nike AF1 Low x Chrome Hearts Olive White", price: 3500, category: "Shoes", brand: "Nike", image_url: "/images/nike-af1-chrome-hearts-olive.jpg" },
  { id: 57, name: "Nike AF1 Low White Silver Chrome Swoosh", price: 3500, category: "Shoes", brand: "Nike", image_url: "/images/nike-af1-chrome-swoosh-white.jpg" },
  { id: 58, name: "Jordan 3 Retro Washed Denim Pink", price: 4500, category: "Shoes", brand: "Jordan", image_url: "/images/jordan-3-washed-denim-pink.jpg" },
  { id: 59, name: "Vans Authentic Corduroy Black White", price: 2500, category: "Shoes", brand: "Vans", image_url: "/images/vans-corduroy-black-white.jpg" },
  { id: 60, name: "Vans Authentic Corduroy Triple Black", price: 2500, category: "Shoes", brand: "Vans", image_url: "/images/vans-corduroy-triple-black.jpg" },
  { id: 61, name: "Nike AF1 Low Pink Beige Gold Charm", price: 3500, category: "Shoes", brand: "Nike", image_url: "/images/nike-af1-pink-beige-gold.jpg" },
  { id: 62, name: "Vans Authentic Corduroy Navy White", price: 2500, category: "Shoes", brand: "Vans", image_url: "/images/vans-corduroy-navy-white.jpg" },
  { id: 63, name: "Vans Authentic Corduroy Grey White", price: 2500, category: "Shoes", brand: "Vans", image_url: "/images/vans-corduroy-grey-white.jpg" },
  { id: 64, name: "Nike AF1 Low Wheat Mocha Black", price: 3500, category: "Shoes", brand: "Nike", image_url: "/images/nike-af1-wheat-mocha.jpg" },
  { id: 65, name: "Nike AF1 Low x Supreme Gucci White Green", price: 3500, category: "Shoes", brand: "Nike", image_url: "/images/nike-af1-supreme-gucci-green.jpg" },
  { id: 66, name: "New Balance 530 White Silver Navy", price: 3000, category: "Shoes", brand: "New Balance", image_url: "/images/nb-530-white-navy.jpg" },
  { id: 67, name: "Nike Air Max 90 Surplus Desert Beige", price: 4000, category: "Shoes", brand: "Nike", image_url: "/images/airmax-90-surplus-beige.jpg" },
  { id: 68, name: "Nike Air Max 90 Surplus Cargo Khaki Volt", price: 4000, category: "Shoes", brand: "Nike", image_url: "/images/airmax-90-surplus-khaki.jpg" },
  { id: 69, name: "Nike Air Max 90 Beige Black Orange", price: 4000, category: "Shoes", brand: "Nike", image_url: "/images/airmax-90-beige-black-orange.jpg" },
  { id: 70, name: "New Balance 530 White Black ABZORB", price: 3500, category: "Shoes", brand: "New Balance", image_url: "/images/nb-530-white-black.jpg" },
  { id: 71, name: "Adidas Samba XLG Platform White Black Gum", price: 3500, category: "Shoes", brand: "Adidas", image_url: "/images/adidas-samba-xlg-platform.jpg" },
  { id: 72, name: "B Logo Light Grey Tan Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/b-logo-light-grey-tan.jpg" },
  { id: 73, name: "Brown Marble Crew Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/brown-marble-crew.jpg" },
  { id: 74, name: "Charcoal Zip Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/charcoal-zip.jpg" },
  { id: 75, name: "Light Grey Zip Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/light-grey-zip.jpg" },
  { id: 76, name: "Navy Zip Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/navy-zip.jpg" },
  { id: 77, name: "Off White Zip Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/off-white-zip.jpg" },
  { id: 78, name: "Black White Striped Polo Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/polo-striped-bw.jpg" },
  { id: 79, name: "Cream Quarter-Zip Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/quarter-cream-lolo.jpg" },
  { id: 80, name: "White Quarter-Zip Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/quarter-white-minimal.jpg" },
  { id: 81, name: "Sage Green Quarter-Zip Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/quarter-sage.jpg" },
  { id: 82, name: "Heather Light Grey Quarter-Zip", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/quarter-heather-light.jpg" },
  { id: 83, name: "Grey Undefeated Quarter-Zip", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/quarter-grey-undef.jpg" },
  { id: 84, name: "Beige 3-Line Quarter-Zip Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/quarter-beige-line.jpg" },
  { id: 85, name: "Cream Undefeated Quarter-Zip", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/quarter-cream-undef.jpg" },
  { id: 86, name: "Cream Oversized Hoodie", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/hoodie-cream.jpg" },
  { id: 87, name: "Navy Pullover Hoodie", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/navy-pullover-hoodie.jpg" },
  { id: 88, name: "Grey Pullover Hoodie", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/grey-pullover-hoodie.jpg" },
  { id: 89, name: "Navy Zip-Up Hoodie", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/navy-zip-hoodie.jpg" },
  { id: 90, name: "Grey Zip-Up Hoodie", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/grey-zip-hoodie.jpg" },
  { id: 91, name: "Cream Zip-Up Hoodie", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/cream-zip-hoodie.jpg" },
  { id: 92, name: "Light Heather Zip Hoodie", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/light-heather-zip-hoodie.jpg" },
  { id: 93, name: "Charcoal Zip-Up Hoodie", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/charcoal-zip-hoodie.jpg" },
  { id: 94, name: "Olive Paint Splatter Quarter-Zip", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/olive-paint-quarter.jpg" },
  { id: 95, name: "Milano Grey Zip Knit Cardigan", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/milano-grey-zip-knit.jpg" },
  { id: 96, name: "White Cable Knit Sweater", price: 2000, category: "Hoods", brand: "Monique", image_url: "/images/sweaters/white-cable-knit.jpg" },
  { id: 97, name: "White Striped Polo With Pocket", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-white-striped-pocket.jpg" },
  { id: 98, name: "White Brown Color Block Polo", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-white-brown-block.jpg" },
  { id: 99, name: "Orange Grey Color Block Polo", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-orange-grey-block.jpg" },
  { id: 100, name: "Navy Blue CK Polo", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-navy-ck.jpg" },
  { id: 101, name: "Charcoal Grey CK Polo", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-charcoal-ck.jpg" },
  { id: 102, name: "White L Huang J Polo", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-white-lhuang-1.jpg" },
  { id: 103, name: "White L Huang J Polo Classic", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-white-lhuang-2.jpg" },
  { id: 104, name: "Black Trendsbar Polo Shirt", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-black-trendsbar.jpg" },
  { id: 105, name: "Off-White Trendsbar Polo Shirt", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-offwhite-trendsbar.jpg" },
  { id: 106, name: "White CK Polo Shirt", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-white-ck-2.jpg" },
  { id: 107, name: "Black CK Polo Shirt", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-black-ck-2.jpg" },
  { id: 108, name: "Taupe Brown Striped Polo With Pocket", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-taupe-brown-striped.jpg" },
  { id: 109, name: "Brown Zip Polo Shirt", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-brown-zip.jpg" },
  { id: 110, name: "Grey Zip Polo Shirt", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-grey-zip.jpg" },
  { id: 111, name: "Beige Zip Polo Shirt", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-beige-zip.jpg" },
  { id: 112, name: "Dark Grey Polo Triangle Logo", price: 2000, category: "Polo Shirts", brand: "Monique", image_url: "/images/sweaters/polo-darkgrey-triangle.jpg" },
  { id: 113, name: "Nike AF1 Low Wheat Mocha Black 2", price: 3500, category: "Shoes", brand: "Nike", image_url: "/images/nike-af1-wheat-black-2.jpg" },
  { id: 114, name: "Vans Authentic Corduroy Black Grey Two-Tone", price: 2500, category: "Shoes", brand: "Vans", image_url: "/images/vans-corduroy-black-grey.jpg" }
];

export default function Home() {
  const [searchParams] = useSearchParams()
  const searchQuery = searchParams.get('search') || ''
  const categoryQuery = searchParams.get('category') || 'All'
  const [products] = useState(HARDCODED_114)
  const [search, setSearch] = useState(searchQuery)
  const [minPrice, setMinPrice] = useState('')
  const [maxPrice, setMaxPrice] = useState('')
  const [selectedBrands, setSelectedBrands] = useState([])
  const [activeCategory, setActiveCategory] = useState(categoryQuery)
  const [showFilters, setShowFilters] = useState(false)

  useEffect(()=>{ setSearch(searchQuery); setActiveCategory(categoryQuery) },[searchQuery, categoryQuery])

  const filtered = products.filter(p=>{
    const s=search.toLowerCase();
    return (!s||p.name.toLowerCase().includes(s)||p.category.toLowerCase().includes(s)||p.brand.toLowerCase().includes(s)) &&
           (!minPrice||p.price>=Number(minPrice)) && (!maxPrice||p.price<=Number(maxPrice)) &&
           (selectedBrands.length===0||selectedBrands.includes(p.brand)) &&
           (activeCategory==='All'|| (categoryMap[activeCategory]?.includes(p.category)))
  });

  const allBrands=[...new Set(products.map(p=>p.brand).filter(Boolean))]
  const toggleBrand=(b)=>setSelectedBrands(prev=>prev.includes(b)?prev.filter(x=>x!==b):[...prev,b])
  const reset=()=>{setSearch('');setMinPrice('');setMaxPrice('');setSelectedBrands([]);setActiveCategory('All')}

  return (
    <div className="min-h-screen bg-[#f5f5f7]">
      <div className="max-w-7xl mx-auto px-3 md:px-6">
        <div className="py-6">
          <h1 className="font-black text-[22px]">MONIQUE INVESTMENTS</h1>
          <p className="text-[13px] text-gray-500">{filtered.length} products ({products.length} total) • Live + Hardcoded</p>
        </div>
        <div className="grid grid-cols-1 lg:grid-cols-[300px_1fr] gap-6">
          <aside className="hidden lg:block sticky top-24 h-fit"><Filters search={search} setSearch={setSearch} minPrice={minPrice} setMinPrice={setMinPrice} maxPrice={maxPrice} setMaxPrice={setMaxPrice} selectedBrands={selectedBrands} toggleBrand={toggleBrand} allBrands={allBrands} resetFilters={reset} /></aside>
          <div className="flex flex-col gap-4">
            <div className="flex justify-end lg:hidden"><button onClick={()=>setShowFilters(true)} className="px-4 py-2 bg-white border rounded-full text-[13px] font-bold">Filters • {filtered.length}</button></div>
            <CategoryFilter activeCategory={activeCategory} onSelect={setActiveCategory} />
            <div className="grid grid-cols-2 md:grid-cols-3 gap-3 md:gap-5">
              {filtered.map(p=><ProductCard key={p.id} product={p} />)}
            </div>
          </div>
        </div>
      </div>
      {showFilters && (
        <div className="lg:hidden fixed inset-0 z-50 bg-black/30" onClick={()=>setShowFilters(false)}>
          <div className="absolute right-0 top-0 h-full w-full max-w-sm p-4 bg-white overflow-y-auto" onClick={e=>e.stopPropagation()}>
            <Filters search={search} setSearch={setSearch} minPrice={minPrice} setMinPrice={setMinPrice} maxPrice={maxPrice} setMaxPrice={setMaxPrice} selectedBrands={selectedBrands} toggleBrand={toggleBrand} allBrands={allBrands} resetFilters={reset} onClose={()=>setShowFilters(false)} />
          </div>
        </div>
      )}
    </div>
  )
}
