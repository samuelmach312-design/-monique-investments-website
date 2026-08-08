import React from 'react'
import { X } from 'lucide-react'

const Filters = ({
  search, setSearch,
  minPrice, setMinPrice,
  maxPrice, setMaxPrice,
  selectedBrands, toggleBrand,
  allBrands, resetFilters, onClose
}) => {
  return (
    <div className="bg-white border border-gray-200 rounded-xl p-6">
      <div className="flex items-center justify-between mb-6">
        <h3 className="text-lg font-bold text-gray-900">Filters</h3>
        {onClose && (
          <button 
            onClick={onClose} 
            className="lg:hidden w-8 h-8 flex items-center justify-center rounded-md text-gray-500 hover:text-gray-900 hover:bg-gray-100 transition-colors"
          >
            <X size={18} />
          </button>
        )}
      </div>

      <div className="flex flex-col gap-6">
        {/* Search - BRIGHT WHITE BG */}
        <div className="flex flex-col gap-2">
          <label className="text-sm font-semibold text-gray-700 uppercase tracking-wide">
            Search
          </label>
          <input
            type="text"
            placeholder="Search products..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full px-4 py-2.5 bg-white border border-gray-300 rounded-lg text-sm text-gray-900 placeholder:text-gray-400 focus:ring-2 focus:ring-gray-900 focus:border-transparent outline-none transition-all"
          />
        </div>

        {/* Price Range - BRIGHT WHITE BG */}
        <div className="flex flex-col gap-2">
          <label className="text-sm font-semibold text-gray-700 uppercase tracking-wide">
            Price Range
          </label>
          <div className="flex items-center gap-3">
            <input
              type="number"
              placeholder="Min"
              value={minPrice}
              onChange={(e) => setMinPrice(e.target.value)}
              className="w-full px-3 py-2.5 bg-white border border-gray-300 rounded-lg text-sm text-gray-900 placeholder:text-gray-400 focus:ring-2 focus:ring-gray-900 focus:border-transparent outline-none"
            />
            <span className="text-gray-400 text-sm">to</span>
            <input
              type="number"
              placeholder="Max"
              value={maxPrice}
              onChange={(e) => setMaxPrice(e.target.value)}
              className="w-full px-3 py-2.5 bg-white border border-gray-300 rounded-lg text-sm text-gray-900 placeholder:text-gray-400 focus:ring-2 focus:ring-gray-900 focus:border-transparent outline-none"
            />
          </div>
        </div>

        {/* Brands - BRIGHT WHITE BG */}
        <div className="flex flex-col gap-2">
          <label className="text-sm font-semibold text-gray-700 uppercase tracking-wide">
            Brands
          </label>
          <div className="flex flex-col gap-2 max-h-48 overflow-y-auto pr-1">
            {allBrands.map(brand => (
              <label 
                key={brand} 
                className={`flex items-center gap-3 px-3 py-2 rounded-lg border cursor-pointer transition-all ${
                  selectedBrands.includes(brand)
                    ? 'border-gray-900 bg-gray-50'
                    : 'border-gray-200 bg-white hover:border-gray-900 hover:bg-gray-50'
                }`}
              >
                <input
                  type="checkbox"
                  checked={selectedBrands.includes(brand)}
                  onChange={() => toggleBrand(brand)}
                  className="w-4 h-4 rounded border-gray-300 text-gray-900 focus:ring-gray-900 focus:ring-offset-0"
                />
                <span className="text-sm text-gray-700">{brand}</span>
              </label>
            ))}
          </div>
        </div>

        {/* Actions */}
        <button
          onClick={resetFilters}
          className="w-full py-2.5 text-sm font-semibold text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 active:scale-[0.98] transition-all"
        >
          Reset Filters
        </button>
      </div>
    </div>
  )
}

export default Filters