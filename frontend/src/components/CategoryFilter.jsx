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
  { name: 'All', emoji: '👟' },
  { name: 'Shoes', emoji: '👟' },
  { name: 'Boots', emoji: '🥾' },
  { name: 'Slides', emoji: '🩴' },
  { name: 'Accessories', emoji: '👔' },
  { name: 'Shoe Care', emoji: '🧴' },
  { name: 'Hoods', emoji: '🧥' },
  { name: 'Polo Shirts', emoji: '👔' }
]

export default function CategoryFilter({ activeCategory, onSelect }) {
  return (
    <div className="bg-[#f5f5f7] py-3">
      <div className="max-w-7xl mx-auto">
        <div className="flex gap-2 overflow-x-auto px-3 pb-2 scrollbar-hide">
          {categories.map((category) => (
            <button
              key={category.name}
              onClick={() => onSelect(category.name)}
              className={`flex items-center gap-1.5 px-4 py-2 rounded-full text-xs font-semibold whitespace-nowrap transition-all duration-200 ${
                activeCategory === category.name
                  ? 'bg-gray-900 text-white shadow-md'
                  : 'bg-white text-gray-700 border border-gray-200 hover:border-gray-300 hover:bg-gray-50'
              }`}
            >
              <span>{category.emoji}</span>
              {category.name}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}