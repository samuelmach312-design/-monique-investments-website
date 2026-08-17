import React, { useState, useEffect } from 'react'
import { useCart } from '../context/CartContext'
import { useSearchParams } from "react-router-dom"
import CategoryFilter, { categoryMap } from '../components/CategoryFilter'
import Filters from '../components/Filters'
import ProductCard from '../components/ProductCard'

export default function Home() {
  const [searchParams] = useSearchParams()
  const searchQuery = searchParams.get('search') || ''
  const categoryQuery = searchParams.get('category') || 'All'

  const [products, setProducts] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

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
        const data = {
          success: true,
          products: [
            // === SHOES ===
            {
              id: 1,
              name: "Grey Casual Brogue Sneakers",
              price: 3500,
              category: "Lifestyle",
              brand: "Monique",
              description: "Grey leather brogue sneakers with white platform sole and brogue detailing. Sizes 40-45",
              image_url: "/images/grey-casual-sneakers.jpg"
            },
            {
              id: 2,
              name: "Grey Suede High-Top Sneakers",
              price: 3500,
              category: "Lifestyle",
              brand: "Monique",
              description: "Grey suede high-top sneakers with gum sole and white midsole. Sizes 40-45",
              image_url: "/images/grey-suede-high-top-sneakers.jpg"
            },
            {
              id: 3,
              name: "Grey Leather Ankle Boots",
              price: 5000,
              category: "Boots",
              brand: "Monique",
              description: "Grey leather ankle boots with white sole and brown accent. Sizes 40-45",
              image_url: "/images/grey-leather-ankle-boots.jpg"
            },
            {
              id: 4,
              name: "Adidas Megashox Black White",
              price: 4000,
              category: "Shoes",
              brand: "Adidas",
              description: "Adidas Megashox in black/white colorway. Sizes 40-45",
              image_url: "/images/adidas-megashox-black-white.jpg"
            },
            {
              id: 5,
              name: "Adidas Megashox Charcoal Black",
              price: 4000,
              category: "Shoes",
              brand: "Adidas",
              description: "Adidas Megashox in charcoal black. Sizes 40-45",
              image_url: "/images/adidas-megashox-charcoal-black.jpg"
            },
            {
              id: 6,
              name: "Black Leather Brogue Shoes",
              price: 5000,
              category: "Shoes",
              brand: "Monique",
              description: "Classic black leather brogue shoes. Sizes 40-45",
              image_url: "/images/black-leather-brogue-shoes.jpg"
            },
            {
              id: 7,
              name: "Canvas Combat Boots Green",
              price: 3800,
              category: "Boots",
              brand: "Monique",
              description: "Canvas combat boots in military green. Sizes 40-45",
              image_url: "/images/canvas-combat-boots-green.jpg"
            },
            {
              id: 8,
              name: "Canvas Combat Boots Tan",
              price: 3800,
              category: "Boots",
              brand: "Monique",
              description: "Canvas combat boots in tan. Sizes 40-45",
              image_url: "/images/canvas-combat-boots-tan.jpg"
            },
            {
              id: 9,
              name: "Versace Style Sneaker Black Teal",
              price: 3500,
              category: "Lifestyle",
              brand: "Monique",
              description: "Chunky platform sneakers black with teal accents. Sizes 40-45",
              image_url: "/images/versace-style-sneaker-black-teal.jpg"
            },
            {
              id: 10,
              name: "Delta Tactical Boots Tan",
              price: 5000,
              category: "Boots",
              brand: "Monique",
              description: "Delta tactical boots in tan. Sizes 40-45",
              image_url: "/images/delta-tactical-boots-tan.jpg"
            },
            {
              id: 11,
              name: "Designer Sneakers Navy",
              price: 3500,
              category: "Shoes",
              brand: "Monique",
              description: "Premium designer sneakers in navy. Sizes 40-45",
              image_url: "/images/designer-sneakers-navy.jpg"
            },
            {
              id: 12,
              name: "Designer Sneakers White",
              price: 3500,
              category: "Shoes",
              brand: "Monique",
              description: "Premium designer sneakers in white. Sizes 40-45",
              image_url: "/images/designer-sneakers-white.jpg"
            },
            {
              id: 13,
              name: "Hiking Shoes AX4 Black",
              price: 3500,
              category: "Shoes",
              brand: "Monique",
              description: "Hiking shoes AX4 in black. Sizes 40-45",
              image_url: "/images/hiking-shoes-ax4-black.jpg"
            },
            {
              id: 14,
              name: "Hiking Shoes AX4 Grey",
              price: 3500,
              category: "Shoes",
              brand: "Monique",
              description: "Hiking shoes AX4 in grey. Sizes 40-45",
              image_url: "/images/hiking-shoes-ax4-grey.jpg"
            },
            {
              id: 15,
              name: "Hiking Shoes AX4 Navy",
              price: 3500,
              category: "Shoes",
              brand: "Monique",
              description: "Hiking shoes AX4 in navy. Sizes 40-45",
              image_url: "/images/hiking-shoes-ax4-navy.jpg"
            },
            {
              id: 16,
              name: "Nike Air Force 1 White",
              price: 2500,
              category: "Shoes",
              brand: "Nike",
              description: "Classic Nike Air Force 1 in triple white. Sizes 40-45",
              image_url: "/images/nike-air-force-1-white.jpg"
            },
            {
              id: 17,
              name: "Nike Air Max 90 Black Volt",
              price: 3500,
              category: "Shoes",
              brand: "Nike",
              description: "Nike Air Max 90 in black/volt. Sizes 40-45",
              image_url: "/images/nike-air-max-90-black-volt.jpg"
            },
            {
              id: 18,
              name: "Nike Air Max 90 Cordura Grey",
              price: 3500,
              category: "Shoes",
              brand: "Nike",
              description: "Nike Air Max 90 Cordura in grey. Sizes 40-45",
              image_url: "/images/nike-air-max-90-cordura-grey.jpg"
            },
            {
              id: 19,
              name: "Work Boots Brown Cat",
              price: 5000,
              category: "Boots",
              brand: "CAT",
              description: "Heavy duty work boots in brown. Sizes 40-45",
              image_url: "/images/work-boots-brown-cat.jpg"
            },
            {
              id: 20,
              name: "Work Boots Grey Cat",
              price: 5000,
              category: "Boots",
              brand: "CAT",
              description: "Heavy duty work boots in grey. Sizes 40-45",
              image_url: "/images/work-boots-grey-cat.jpg"
            },
            {
              id: 21,
              name: "Tactical Combat Boots Beige",
              price: 5000,
              category: "Boots",
              brand: "Monique",
              description: "Tactical combat boots in beige. Sizes 40-45",
              image_url: "/images/tactical-combat-boots-beige.jpg"
            },
            {
              id: 22,
              name: "Tan Leather Chukka Boots",
              price: 5000,
              category: "Boots",
              brand: "Monique",
              description: "Classic tan leather chukka boots. Sizes 40-45",
              image_url: "/images/tan-leather-chukka-boots.jpg"
            },
            {
              id: 23,
              name: "Running Sneakers Grey Brown",
              price: 3000,
              category: "Shoes",
              brand: "Monique",
              description: "Performance running sneakers in grey/brown. Sizes 40-45",
              image_url: "/images/running-sneakers-grey-brown.jpg"
            },
            {
              id: 24,
              name: "Versace Style Sneaker Black White",
              price: 3500,
              category: "Lifestyle",
              brand: "Monique",
              description: "Luxury style sneaker in black/white. Sizes 40-45",
              image_url: "/images/versace-style-sneaker-black-white.jpg"
            },
            {
              id: 25,
              name: "Motorsport Sneakers Black Red",
              price: 4000,
              category: "Lifestyle",
              brand: "Monique",
              description: "Motorsport inspired sneakers black/red. Sizes 40-45",
              image_url: "/images/motorsport-sneakers-black-red.jpg"
            },
            {
              id: 26,
              name: "Motorsport Sneakers Black White",
              price: 4000,
              category: "Lifestyle",
              brand: "Monique",
              description: "Motorsport inspired sneakers black/white. Sizes 40-45",
              image_url: "/images/motorsport-sneakers-black-white.jpg"
            },
            {
              id: 27,
              name: "Naked Wolfe Slider Black White",
              price: 3500,
              category: "Slides",
              brand: "Monique",
              description: "Comfortable sliders in black/white. Sizes 40-45",
              image_url: "/images/naked-wolfe-slider-black-white.jpg"
            },
            {
              id: 28,
              name: "Naked Wolfe Slider Triple Black",
              price: 3500,
              category: "Slides",
              brand: "Monique",
              description: "All black premium sliders. Sizes 40-45",
              image_url: "/images/naked-wolfe-slider-triple-black.jpg"
            },

            // === BELTS ===
            {
              id: 29,
              name: "Braided Belt Brown",
              price: 800,
              category: "Accessories",
              brand: "Monique",
              description: "Premium braided leather belt in brown. One size fits all",
              image_url: "/images/braided-belt-brown.jpg"
            },
            {
              id: 30,
              name: "Canvas Belt Tan",
              price: 1000,
              category: "Accessories",
              brand: "Monique",
              description: "Durable canvas belt in tan. Adjustable",
              image_url: "/images/canvas-belt-tan.jpg"
            },
            {
              id: 31,
              name: "Leather Belt Black",
              price: 1200,
              category: "Accessories",
              brand: "Monique",
              description: "Classic black leather belt with silver buckle. Sizes 32-42",
              image_url: "/images/leather-belt-black.jpg"
            },

            // === SHOE LACES ===
            {
              id: 32,
              name: "Elastic Shoe Laces",
              price: 200,
              category: "Accessories",
              brand: "Monique",
              description: "No-tie elastic shoe laces. One size",
              image_url: "/images/elastic-shoe-laces.jpg"
            },
            {
              id: 33,
              name: "Jordan & Dunk Replacement Laces",
              price: 100,
              category: "Accessories",
              brand: "Monique",
              description: "Premium replacement laces for Jordan & Dunk sneakers",
              image_url: "/images/jordan-and-dunk-replacement-shoe-laces.jpg"
            },
            {
              id: 34,
              name: "Thick Rope Shoe Laces",
              price: 150,
              category: "Accessories",
              brand: "Monique",
              description: "Heavy duty thick rope laces for boots",
              image_url: "/images/thick-rope-shoe-laces.jpg"
            },

            // === SHOE CARE ===
            {
              id: 35,
              name: "Shoe Foam Cleaner",
              price: 400,
              category: "Shoe Care",
              brand: "Monique",
              description: "Professional foam cleaner for all shoe types. 200ml",
              image_url: "/images/shoe-foam-cleaner.jpg"
            },
            {
              id: 36,
              name: "Shoe Horn",
              price: 400,
              category: "Shoe Care",
              brand: "Monique",
              description: "Stainless steel shoe horn for easy wearing",
              image_url: "/images/shoe-horn.jpg"
            },
            {
              id: 37,
              name: "Handtowels",
              price: 100,
              category: "Shoe Care",
              brand: "Monique",
              description: "Microfiber kitchen handtowels - long version. Multiple colors: blue, purple, yellow, red, green.",
              image_url: "/images/handtowels.jpg"
            },
            {
              id: 38,
              name: "Adidas Samba Black White",
              price: 3500,
              category: "Shoes",
              brand: "Adidas",
              description: "Adidas Samba Black White - classic sneakers. Sizes 40-45",
              image_url: "/images/samba.jpg"
            },
          ]
        }

        if (data.success) {
          setProducts(data.products)
        } else {
          setError('Failed to load products')
        }
      } catch (err) {
        console.error('Error:', err)
        setError('Could not load products')
      } finally {
        setLoading(false)
      }
    }

    fetchProducts()
  }, [])

  useEffect(() => {
    setSearch(searchQuery)
    setActiveCategory(categoryQuery)
  }, [searchQuery, categoryQuery])

  const filteredProducts = products.filter(product => {
    const searchLower = search.toLowerCase().trim()

    const matchesSearch =!searchLower ||
      product.name?.toLowerCase().includes(searchLower) ||
      product.category?.toLowerCase().includes(searchLower) ||
      product.description?.toLowerCase().includes(searchLower) ||
      product.brand?.toLowerCase().includes(searchLower)

    const matchesPrice =
      (!minPrice || Number(product.price) >= Number(minPrice)) &&
      (!maxPrice || Number(product.price) <= Number(maxPrice))

    const matchesBrand =
      selectedBrands.length === 0 || selectedBrands.includes(product.brand)

    const allowedCategories = categoryMap[activeCategory]
    const matchesCategory =
      activeCategory === 'All' ||
      (allowedCategories && allowedCategories.length > 0 && allowedCategories.includes(product.category))

    return matchesSearch && matchesPrice && matchesBrand && matchesCategory
  })

  const allBrands = [...new Set(products.map(p => p.brand).filter(Boolean))]

  const toggleBrand = (brand) => {
    setSelectedBrands(prev =>
      prev.includes(brand)? prev.filter(b => b!== brand) : [...prev, brand]
    )
  }

  const resetFilters = () => {
    setSearch('')
    setMinPrice('')
    setMaxPrice('')
    setSelectedBrands([])
    setActiveCategory('All')
  }

  if (loading) return (
    <div className="min-h-screen bg-[#f5f5f7] flex items-center justify-center">
      <div className="text-gray-500 text-lg">Loading products...</div>
    </div>
  )

  if (error) return (
    <div className="min-h-screen bg-[#f5f5f7] flex items-center justify-center">
      <div className="text-red-500 text-lg">{error}</div>
    </div>
  )

  return (
    <div className="min-h-screen bg-[#f5f5f7] w-full overflow-x-hidden">
      <div className="w-full max-w-7xl mx-auto">
        {/* JUMIA STYLE HEADER */}
        <div className="page-header">
          <h1>Monique Investments</h1>
          <div className="page-header-row">
            <h2>{activeCategory === 'All'? 'All Products' : activeCategory}</h2>
            <span className="product-count">{filteredProducts.length} products</span>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-[320px_1fr] gap-4 md:gap-8 w-full">
          <aside className="hidden lg:block h-fit lg:sticky lg:top-24">
            <Filters
              search={search}
              setSearch={setSearch}
              minPrice={minPrice}
              setMinPrice={setMinPrice}
              maxPrice={maxPrice}
              setMaxPrice={setMaxPrice}
              selectedBrands={selectedBrands}
              toggleBrand={toggleBrand}
              allBrands={allBrands}
              resetFilters={resetFilters}
            />
          </aside>

          <div className="flex flex-col gap-4 sm:gap-6 w-full min-w-0">
            <div className="flex items-center justify-end gap-2 lg:hidden px-3">
              <button
                onClick={() => setShowFilters(true)}
                className="px-3 py-2 bg-white border border-gray-200 text-gray-800 rounded-lg hover:bg-gray-50 transition-colors text-sm min-h-11"
              >
                Filters
              </button>
            </div>

            <CategoryFilter
              activeCategory={activeCategory}
              onSelect={setActiveCategory}
            />

            {/* THIS IS THE JUMIA FIX: grid-cols-2 on mobile */}
            <div className="products-grid">
              {filteredProducts.length === 0? (
                <div className="col-span-full text-center text-gray-500 py-16">
                  <p className="text-base sm:text-lg mb-4">
                    {search? `No products found for "${search}"` : 'No products found. Try adjusting filters.'}
                  </p>
                  <button
                    onClick={resetFilters}
                    className="px-4 py-2 text-sm text-[#e93a0e] hover:underline font-medium min-h-11"
                  >
                    Clear filters
                  </button>
                </div>
              ) : filteredProducts.map(product => (
                <ProductCard key={product.id} product={product} />
              ))}
            </div>
          </div>
        </div>
      </div>

      {showFilters && (
        <div className="lg:hidden fixed inset-0 z-50 bg-black/30 backdrop-blur-sm" onClick={() => setShowFilters(false)}>
          <div className="absolute right-0 top-0 h-full w-full max-w-sm p-4" onClick={e => e.stopPropagation()}>
            <Filters
              search={search}
              setSearch={setSearch}
              minPrice={minPrice}
              setMinPrice={setMinPrice}
              maxPrice={maxPrice}
              setMaxPrice={setMaxPrice}
              selectedBrands={selectedBrands}
              toggleBrand={toggleBrand}
              allBrands={allBrands}
              resetFilters={resetFilters}
              onClose={() => setShowFilters(false)}
            />
          </div>
        </div>
      )}
    </div>
  )
}

