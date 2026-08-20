import React from 'react'

export default function Filters({
  search,
  setSearch,
  minPrice,
  setMinPrice,
  maxPrice,
  setMaxPrice,
  selectedBrands,
  toggleBrand,
  allBrands,
  resetFilters,
  onClose
}) {
  return (
    <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-5 flex flex-col gap-6 h-fit">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h3 className="text- font-bold text-gray-900 tracking-tight flex items-center gap-2">
          <span className="w-1 h-5 bg-blue-600 rounded-full"></span>
          Filters
        </h3>
        {onClose && (
          <button
            onClick={onClose}
            className="lg:hidden w-8 h-8 rounded-full bg-gray-50 flex items-center justify-center text-gray-500 hover:bg-gray-100"
          >
            ✕
          </button>
        )}
      </div>

      {/* SEARCH */}
      <div className="space-y-3">
        <label className="text- font-bold text-gray-500 uppercase tracking-widest">
          Search
        </label>
        <div className="relative">
          <span className="absolute left-3.5 top-1/2 -translate-y-1/2 text-gray-400">
            <svg width="16" height="16" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
            </svg>
          </span>
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search products..."
            className="w-full pl-10 pr-4 py-3 bg-gray-50 border border-gray-200 rounded-xl text-sm font-medium text-gray-900 placeholder:text-gray-400 focus:outline-none focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-50 transition-all"
          />
        </div>
      </div>

      {/* PRICE RANGE */}
      <div className="space-y-3">
        <label className="text- font-bold text-gray-500 uppercase tracking-widest">
          Price Range
        </label>
        <div className="flex items-center gap-2">
          <div className="relative flex-1">
            <span className="absolute left-3 top-1/2 -translate-y-1/2 text- font-bold text-gray-400">KES</span>
            <input
              type="number"
              value={minPrice}
              onChange={(e) => setMinPrice(e.target.value)}
              placeholder="Min"
              className="w-full pl-10 pr-3 py-3 bg-gray-50 border border-gray-200 rounded-xl text-sm font-medium focus:outline-none focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-50 transition-all"
            />
          </div>
          <span className="text-xs font-bold text-gray-300">—</span>
          <div className="relative flex-1">
            <span className="absolute left-3 top-1/2 -translate-y-1/2 text- font-bold text-gray-400">KES</span>
            <input
              type="number"
              value={maxPrice}
              onChange={(e) => setMaxPrice(e.target.value)}
              placeholder="Max"
              className="w-full pl-10 pr-3 py-3 bg-gray-50 border border-gray-200 rounded-xl text-sm font-medium focus:outline-none focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-50 transition-all"
            />
          </div>
        </div>
      </div>

      {/* BRANDS */}
      <div className="space-y-3">
        <label className="text- font-bold text-gray-500 uppercase tracking-widest flex items-center justify-between">
          Brands
          {selectedBrands.length > 0 && (
            <span className="bg-blue-600 text-white text- px-2 py-0.5 rounded-full font-bold">
              {selectedBrands.length}
            </span>
          )}
        </label>
        <div className="space-y-2 max-h- overflow-y-auto pr-1 scrollbar-hide">
          {allBrands.map((brand) => {
            const isSelected = selectedBrands.includes(brand)
            return (
              <label
                key={brand}
                className={`flex items-center gap-3 px-3.5 py-2.5 rounded-xl border cursor-pointer transition-all group ${
                  isSelected
                   ? 'bg-blue-50 border-blue-200 shadow-sm'
                    : 'bg-white border-gray-100 hover:border-gray-200 hover:bg-gray-50'
                }`}
              >
                <div className="relative flex items-center">
                  <input
                    type="checkbox"
                    checked={isSelected}
                    onChange={() => toggleBrand(brand)}
                    className="peer sr-only"
                  />
                  <div className={`w-5 h-5 rounded-md border-2 flex items-center justify-center transition-all ${
                    isSelected
                     ? 'bg-blue-600 border-blue-600'
                      : 'bg-white border-gray-300 group-hover:border-gray-400'
                  }`}>
                    {isSelected && (
                      <svg className="w-3 h-3 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                        <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="3" d="M5 13l4 4L19 7" />
                      </svg>
                    )}
                  </div>
                </div>
                <span className={`text-sm font-medium flex-1 ${
                  isSelected? 'text-blue-900' : 'text-gray-700'
                }`}>
                  {brand}
                </span>
              </label>
            )
          })}
        </div>
      </div>

      {/* RESET BUTTON */}
      <button
        onClick={resetFilters}
        className="w-full py-3.5 bg-gray-900 hover:bg-black text-white rounded-xl text-sm font-bold tracking-wide transition-all shadow-sm hover:shadow-md active:scale-[0.98]"
      >
        Reset Filters
      </button>

      <p className="text- text-center text-gray-400 font-medium">
        {allBrands.length} brands • Professional filters
      </p>
    </div>
  )
}