import React, { useState } from 'react'

const API_BASE = (import.meta.env.VITE_API_URL || 'https://monique-backend.onrender.com/api').replace(/\/$/, '');
const API = `${API_BASE}/mongo-products`;

const PRODUCTS_114 = [
  { name: "Grey Casual Brogue Sneakers", sellingPrice: 3500, category: "Lifestyle", brand: "Monique", image: "/images/grey-casual-sneakers.jpg", stock: 50 },
  { name: "Grey Suede High-Top Sneakers", sellingPrice: 3500, category: "Lifestyle", brand: "Monique", image: "/images/grey-suede-high-top-sneakers.jpg", stock: 50 },
  { name: "Grey Leather Ankle Boots", sellingPrice: 5000, category: "Boots", brand: "Monique", image: "/images/grey-leather-ankle-boots.jpg", stock: 50 },
  { name: "Adidas Megashox Black White", sellingPrice: 4000, category: "Shoes", brand: "Adidas", image: "/images/adidas-megashox-black-white.jpg", stock: 50 },
  { name: "Adidas Megashox Charcoal Black", sellingPrice: 4000, category: "Shoes", brand: "Adidas", image: "/images/adidas-megashox-charcoal-black.jpg", stock: 50 },
  { name: "Black Leather Brogue Shoes", sellingPrice: 5000, category: "Shoes", brand: "Monique", image: "/images/black-leather-brogue-shoes.jpg", stock: 50 },
  { name: "Canvas Combat Boots Green", sellingPrice: 3800, category: "Boots", brand: "Monique", image: "/images/canvas-combat-boots-green.jpg", stock: 50 },
  { name: "Canvas Combat Boots Tan", sellingPrice: 3800, category: "Boots", brand: "Monique", image: "/images/canvas-combat-boots-tan.jpg", stock: 50 },
  { name: "Versace Style Sneaker Black Teal", sellingPrice: 3500, category: "Lifestyle", brand: "Monique", image: "/images/versace-style-sneaker-black-teal.jpg", stock: 50 },
  { name: "Delta Tactical Boots Tan", sellingPrice: 5000, category: "Boots", brand: "Monique", image: "/images/delta-tactical-boots-tan.jpg", stock: 50 },
  { name: "Designer Sneakers Navy", sellingPrice: 3500, category: "Shoes", brand: "Monique", image: "/images/designer-sneakers-navy.jpg", stock: 50 },
  { name: "Designer Sneakers White", sellingPrice: 3500, category: "Shoes", brand: "Monique", image: "/images/designer-sneakers-white.jpg", stock: 50 },
  { name: "Hiking Shoes AX4 Black", sellingPrice: 3500, category: "Shoes", brand: "Monique", image: "/images/hiking-shoes-ax4-black.jpg", stock: 50 },
  { name: "Hiking Shoes AX4 Grey", sellingPrice: 3500, category: "Shoes", brand: "Monique", image: "/images/hiking-shoes-ax4-grey.jpg", stock: 50 },
  { name: "Hiking Shoes AX4 Navy", sellingPrice: 3500, category: "Shoes", brand: "Monique", image: "/images/hiking-shoes-ax4-navy.jpg", stock: 50 },
  { name: "Nike Air Force 1 White", sellingPrice: 2500, category: "Shoes", brand: "Nike", image: "/images/nike-air-force-1-white.jpg", stock: 50 },
  { name: "Nike Air Max 90 Black Volt", sellingPrice: 3500, category: "Shoes", brand: "Nike", image: "/images/nike-air-max-90-black-volt.jpg", stock: 50 },
  { name: "Nike Air Max 90 Cordura Grey", sellingPrice: 3500, category: "Shoes", brand: "Nike", image: "/images/nike-air-max-90-cordura-grey.jpg", stock: 50 },
  { name: "Work Boots Brown Cat", sellingPrice: 5000, category: "Boots", brand: "CAT", image: "/images/work-boots-brown-cat.jpg", stock: 50 },
  { name: "Work Boots Grey Cat", sellingPrice: 5000, category: "Boots", brand: "CAT", image: "/images/work-boots-grey-cat.jpg", stock: 50 },
  { name: "Tactical Combat Boots Beige", sellingPrice: 5000, category: "Boots", brand: "Monique", image: "/images/tactical-combat-boots-beige.jpg", stock: 50 },
  { name: "Tan Leather Chukka Boots", sellingPrice: 5000, category: "Boots", brand: "Monique", image: "/images/tan-leather-chukka-boots.jpg", stock: 50 },
  { name: "Running Sneakers Grey Brown", sellingPrice: 3000, category: "Shoes", brand: "Monique", image: "/images/running-sneakers-grey-brown.jpg", stock: 50 },
  { name: "Versace Style Sneaker Black White", sellingPrice: 3500, category: "Lifestyle", brand: "Monique", image: "/images/versace-style-sneaker-black-white.jpg", stock: 50 },
  { name: "Motorsport Sneakers Black Red", sellingPrice: 4000, category: "Lifestyle", brand: "Monique", image: "/images/motorsport-sneakers-black-red.jpg", stock: 50 },
  { name: "Motorsport Sneakers Black White", sellingPrice: 4000, category: "Lifestyle", brand: "Monique", image: "/images/motorsport-sneakers-black-white.jpg", stock: 50 },
  { name: "Naked Wolfe Slider Black White", sellingPrice: 3500, category: "Slides", brand: "Monique", image: "/images/naked-wolfe-slider-black-white.jpg", stock: 50 },
  { name: "Naked Wolfe Slider Triple Black", sellingPrice: 3500, category: "Slides", brand: "Monique", image: "/images/naked-wolfe-slider-triple-black.jpg", stock: 50 },
  { name: "Braided Belt Brown", sellingPrice: 800, category: "Accessories", brand: "Monique", image: "/images/braided-belt-brown.jpg", stock: 50 },
  { name: "Canvas Belt Tan", sellingPrice: 1000, category: "Accessories", brand: "Monique", image: "/images/canvas-belt-tan.jpg", stock: 50 },
  { name: "Leather Belt Black", sellingPrice: 1200, category: "Accessories", brand: "Monique", image: "/images/leather-belt-black.jpg", stock: 50 },
  { name: "Elastic Shoe Laces", sellingPrice: 200, category: "Accessories", brand: "Monique", image: "/images/elastic-shoe-laces.jpg", stock: 50 },
  { name: "Jordan & Dunk Replacement Laces", sellingPrice: 100, category: "Accessories", brand: "Monique", image: "/images/jordan-and-dunk-replacement-shoe-laces.jpg", stock: 50 },
  { name: "Thick Rope Shoe Laces", sellingPrice: 150, category: "Accessories", brand: "Monique", image: "/images/thick-rope-shoe-laces.jpg", stock: 50 },
  { name: "Shoe Foam Cleaner", sellingPrice: 400, category: "Shoe Care", brand: "Monique", image: "/images/shoe-foam-cleaner.jpg", stock: 50 },
  { name: "Shoe Horn", sellingPrice: 400, category: "Shoe Care", brand: "Monique", image: "/images/shoe-horn.jpg", stock: 50 },
  { name: "Handtowels", sellingPrice: 200, category: "Shoe Care", brand: "Monique", image: "/images/handtowels.jpg", stock: 50 },
  { name: "Adidas Samba Black White", sellingPrice: 3500, category: "Shoes", brand: "Adidas", image: "/images/samba.jpg", stock: 50 },
  { name: "Nike Air Force 1 Undefeated Beige Navy", sellingPrice: 3500, category: "Shoes", brand: "Nike", image: "/images/nike-af1-undefeated-beige.jpg", stock: 50 },
  { name: "Nike Air Force 1 White Burgundy", sellingPrice: 3500, category: "Shoes", brand: "Nike", image: "/images/nike-af1-white-burgundy.jpg", stock: 50 },
  { name: "Nike Air Max 90 Surplus Grey", sellingPrice: 3500, category: "Shoes", brand: "Nike", image: "/images/nike-air-max-90-grey-surplus.jpg", stock: 50 },
  { name: "Jordan 1 Low Travis Olive Brown", sellingPrice: 4000, category: "Shoes", brand: "Jordan", image: "/images/jordan-1-low-travis-olive.jpg", stock: 50 },
];

export default function Seed114() {
  const [log, setLog] = useState([]);
  const [seeding, setSeeding] = useState(false);
  const [done, setDone] = useState(0);

  const seed = async () => {
    setSeeding(true);
    setLog([]);
    setDone(0);
    let ok = 0;
    for (const p of PRODUCTS_114) {
      try {
        const res = await fetch(API, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(p)
        });
        if (res.ok) {
          ok++;
          setDone(ok);
          setLog(l => [`✅ ${p.name}`, ...l].slice(0,20));
        } else {
          const t = await res.text();
          setLog(l => [`❌ ${p.name} - ${t.slice(0,80)}`, ...l].slice(0,20));
        }
      } catch (e) {
        setLog(l => [`❌ ${p.name} - ${e.message}`, ...l].slice(0,20));
      }
    }
    setSeeding(false);
    alert(`Done! Seeded ${ok}/114. Now Admin will show 114.`);
  };

  return (
    <div className="min-h-screen bg-gray-50 p-6 max-w-3xl mx-auto">
      <h1 className="text-2xl font-black">SEED 114 → Mongo</h1>
      <p className="text-sm text-gray-600 mt-2">This uploads your 114 hardcoded products to Render Mongo so Admin shows 114 not 39.</p>
      <p className="text-xs mt-1">API: {API}</p>
      <button onClick={seed} disabled={seeding} className="mt-6 px-6 py-3 bg-black text-white rounded-full font-bold disabled:opacity-50">
        {seeding ? `Seeding ${done}/114...` : 'SEED 114 → Mongo'}
      </button>
      <div className="mt-6 bg-white border rounded-xl p-4 h-96 overflow-auto font-mono text-xs">
        {log.map((l,i)=><div key={i}>{l}</div>)}
        {!log.length && <div className="text-gray-400">Logs appear here...</div>}
      </div>
    </div>
  );
}
