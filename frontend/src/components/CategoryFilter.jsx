import React from 'react'

export const categoryMap = {
  'All': [],
  'Shoes': ['Shoes', 'Running', 'Lifestyle', 'Sneakers', 'Skate', 'Basketball', 'Casual'],
  'Boots': ['Boots'],
  'Slides': ['Slides'],
  'Accessories': ['Accessories'],
  'Shoe Care': ['Shoe Care'],
  'Hoods': ['Hoods'],
  'Polo Shirts': ['Polo Shirts']
}

const categories = [
  { name: 'All', icon: '◉', count: null },
  { name: 'Shoes', icon: '👟', count: null },
  { name: 'Boots', icon: '🥾', count: null },
  { name: 'Slides', icon: '🩴', count: null },
  { name: 'Accessories', icon: '🎒', count: null },
  { name: 'Shoe Care', icon: '✨', count: null },
  { name: 'Hoods', icon: '🧥', count: null },
  { name: 'Polo Shirts', icon: '👔', count: null }
]

export default function CategoryFilter({ activeCategory, onSelect }) {
  return (
    <div className="bg-white border-b border-gray-100 sticky top-0 z-20 backdrop-blur-xl bg-white/90">
      <div className="max-w-7xl mx-auto">
        <div className="flex gap-2.5 overflow-x-auto px-3 py-3.5 scrollbar-hide">
          {categories.map((category) => {
            const isActive = activeCategory === category.name
            return (
              <button
                key={category.name}
                onClick={() => onSelect(category.name)}
                className={`group flex items-center gap-2 px-5 py-2.5 rounded-full text- font-bold whitespace-nowrap transition-all duration-200 border ${
                  isActive
                    ? 'bg-[#0f172a] text-white border-[#0f172a] shadow-lg shadow-blue-900/20 scale-[1.02]'
                    : 'bg-gray-50 text-gray-600 border-gray-200 hover:bg-white hover:border-gray-300 hover:text-gray-900 hover:shadow-sm'
                }`}
              >
                <span className={`text- transition-transform group-hover:scale-110 ${isActive ? '' : 'opacity-80'}`}>
                  {category.icon}
                </span>
                <span className="tracking-wide">{category.name}</span>
                {isActive && (
                  <span className="w-1.5 h-1.5 bg-blue-400 rounded-full ml-1 animate-pulse"></span>
                )}
              </button>
            )
          })}
        </div>
      </div>
    </div>
  )
}