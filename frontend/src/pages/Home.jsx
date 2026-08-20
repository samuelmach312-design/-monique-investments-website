import React, { useState, useEffect } from 'react'
import { useCart } from '../context/CartContext'
import { useSearchParams } from "react-router-dom"
import CategoryFilter, { categoryMap } from '../components/CategoryFilter'
import Filters from '../components/Filters'
import ProductCard from '../components/ProductCard'
import { getProducts } from '../services/api'

const HARDCODED_PRODUCTS = [
  { id: 1, name: "Grey Casual Brogue Sneakers", price: 3500, category: "Lifestyle", brand: "Monique", description: "Grey leather brogue sneakers with white platform sole and brogue detailing. Sizes 40-45", image_url: "/images/grey-casual-sneakers.jpg" },
  { id: 2, name: "Grey Suede High-Top Sneakers", price: 3500, category: "Lifestyle", brand: "Monique", description: "Grey suede high-top sneakers with gum sole and white midsole. Sizes 40-45", image_url: "/images/grey-suede-high-top-sneakers.jpg" },
  { id: 3, name: "Grey Leather Ankle Boots", price: 5000, category: "Boots", brand: "Monique", description: "Grey leather ankle boots with white sole and brown accent. Sizes 40-45", image_url: "/images/grey-leather-ankle-boots.jpg" },
  { id: 4, name: "Adidas Megashox Black White", price: 4000, category: "Shoes", brand: "Adidas", description: "Adidas Megashox in black/white colorway. Sizes 40-45", image_url: "/images/adidas-megashox-black-white.jpg" },
  { id: 5, name: "Adidas Megashox Charcoal Black", price: 4000, category: "Shoes", brand: "Adidas", description: "Adidas Megashox in charcoal black. Sizes 40-45", image_url: "/images/adidas-megashox-charcoal-black.jpg" },
  { id: 6, name: "Black Leather Brogue Shoes", price: 5000, category: "Shoes", brand: "Monique", description: "Classic black leather brogue shoes. Sizes 40-45", image_url: "/images/black-leather-brogue-shoes.jpg" },
  { id: 7, name: "Canvas Combat Boots Green", price: 3800, category: "Boots", brand: "Monique", description: "Canvas combat boots in military green. Sizes 40-45", image_url: "/images/canvas-combat-boots-green.jpg" },
  { id: 8, name: "Canvas Combat Boots Tan", price: 3800, category: "Boots", brand: "Monique", description: "Canvas combat boots in tan. Sizes 40-45", image_url: "/images/canvas-combat-boots-tan.jpg" },
  { id: 9, name: "Versace Style Sneaker Black Teal", price: 3500, category: "Lifestyle", brand: "Monique", description: "Chunky platform sneakers black with teal accents. Sizes 40-45", image_url: "/images/versace-style-sneaker-black-teal.jpg" },
  { id: 10, name: "Delta Tactical Boots Tan", price: 5000, category: "Boots", brand: "Monique", description: "Delta tactical boots in tan. Sizes 40-45", image_url: "/images/delta-tactical-boots-tan.jpg" },
  { id: 11, name: "Designer Sneakers Navy", price: 3500, category: "Shoes", brand: "Monique", description: "Premium designer sneakers in navy. Sizes 40-45", image_url: "/images/designer-sneakers-navy.jpg" },
  { id: 12, name: "Designer Sneakers White", price: 3500, category: "Shoes", brand: "Monique", description: "Premium designer sneakers in white. Sizes 40-45", image_url: "/images/designer-sneakers-white.jpg" },
  { id: 13, name: "Hiking Shoes AX4 Black", price: 3500, category: "Shoes", brand: "Monique", description: "Hiking shoes AX4 in black. Sizes 40-45", image_url: "/images/hiking-shoes-ax4-black.jpg" },
  { id: 14, name: "Hiking Shoes AX4 Grey", price: 3500, category: "Shoes", brand: "Monique", description: "Hiking shoes AX4 in grey. Sizes 40-45", image_url: "/images/hiking-shoes-ax4-grey.jpg" },
  { id: 15, name: "Hiking Shoes AX4 Navy", price: 3500, category: "Shoes", brand: "Monique", description: "Hiking shoes AX4 in navy. Sizes 40-45", image_url: "/images/hiking-shoes-ax4-navy.jpg" },
  { id: 16, name: "Nike Air Force 1 White", price: 2500, category: "Shoes", brand: "Nike", description: "Classic Nike Air Force 1 in triple white. Sizes 40-45", image_url: "/images/nike-air-force-1-white.jpg" },
  { id: 17, name: "Nike Air Max 90 Black Volt", price: 3500, category: "Shoes", brand: "Nike", description: "Nike Air Max 90 in black/volt. Sizes 40-45", image_url: "/images/nike-air-max-90-black-volt.jpg" },
  { id: 18, name: "Nike Air Max 90 Cordura Grey", price: 3500, category: "Shoes", brand: "Nike", description: "Nike Air Max 90 Cordura in grey. Sizes 40-45", image_url: "/images/nike-air-max-90-cordura-grey.jpg" },
  { id: 19, name: "Work Boots Brown Cat", price: 5000, category: "Boots", brand: "CAT", description: "Heavy duty work boots in brown. Sizes 40-45", image_url: "/images/work-boots-brown-cat.jpg" },
  { id: 20, name: "Work Boots Grey Cat", price: 5000, category: "Boots", brand: "CAT", description: "Heavy duty work boots in grey. Sizes 40-45", image_url: "/images/work-boots-grey-cat.jpg" },
  { id: 21, name: "Tactical Combat Boots Beige", price: 5000, category: "Boots", brand: "Monique", description: "Tactical combat boots in beige. Sizes 40-45", image_url: "/images/tactical-combat-boots-beige.jpg" },
  { id: 22, name: "Tan Leather Chukka Boots", price: 5000, category: "Boots", brand: "Monique", description: "Classic tan leather chukka boots. Sizes 40-45", image_url: "/images/tan-leather-chukka-boots.jpg" },
  { id: 23, name: "Running Sneakers Grey Brown", price: 3000, category: "Shoes", brand: "Monique", description: "Performance running sneakers in grey/brown. Sizes 40-45", image_url: "/images/running-sneakers-grey-brown.jpg" },
  { id: 24, name: "Versace Style Sneaker Black White", price: 3500, category: "Lifestyle", brand: "Monique", description: "Luxury style sneaker in black/white. Sizes 40-45", image_url: "/images/versace-style-sneaker-black-white.jpg" },
  { id: 25, name: "Motorsport Sneakers Black Red", price: 4000, category: "Lifestyle", brand: "Monique", description: "Motorsport inspired sneakers black/red. Sizes 40-45", image_url: "/images/motorsport-sneakers-black-red.jpg" },
  { id: 26, name: "Motorsport Sneakers Black White", price: 4000, category: "Lifestyle", brand: "Monique", description: "Motorsport inspired sneakers black/white. Sizes 40-45", image_url: "/images/motorsport-sneakers-black-white.jpg" },
  { id: 27, name: "Naked Wolfe Slider Black White", price: 3500, category: "Slides", brand: "Monique", description: "Comfortable sliders in black/white. Sizes 40-45", image_url: "/images/naked-wolfe-slider-black-white.jpg" },
  { id: 28, name: "Naked Wolfe Slider Triple Black", price: 3500, category: "Slides", brand: "Monique", description: "All black premium sliders. Sizes 40-45", image_url: "/images/naked-wolfe-slider-triple-black.jpg" },
  { id: 29, name: "Braided Belt Brown", price: 800, category: "Accessories", brand: "Monique", description: "Premium braided leather belt in brown. One size fits all", image_url: "/images/braided-belt-brown.jpg" },
  { id: 30, name: "Canvas Belt Tan", price: 1000, category: "Accessories", brand: "Monique", description: "Durable canvas belt in tan. Adjustable", image_url: "/images/canvas-belt-tan.jpg" },
  { id: 31, name: "Leather Belt Black", price: 1200, category: "Accessories", brand: "Monique", description: "Classic black leather belt with silver buckle. Sizes 32-42", image_url: "/images/leather-belt-black.jpg" },
  { id: 32, name: "Elastic Shoe Laces", price: 200, category: "Accessories", brand: "Monique", description: "No-tie elastic shoe laces. One size", image_url: "/images/elastic-shoe-laces.jpg" },
  { id: 33, name: "Jordan & Dunk Replacement Laces", price: 100, category: "Accessories", brand: "Monique", description: "Premium replacement laces for Jordan & Dunk sneakers", image_url: "/images/jordan-and-dunk-replacement-shoe-laces.jpg" },
  { id: 34, name: "Thick Rope Shoe Laces", price: 150, category: "Accessories", brand: "Monique", description: "Heavy duty thick rope laces for boots", image_url: "/images/thick-rope-shoe-laces.jpg" },
  { id: 35, name: "Shoe Foam Cleaner", price: 400, category: "Shoe Care", brand: "Monique", description: "Professional foam cleaner for all shoe types. 200ml", image_url: "/images/shoe-foam-cleaner.jpg" },
  { id: 36, name: "Shoe Horn", price: 400, category: "Shoe Care", brand: "Monique", description: "Stainless steel shoe horn for easy wearing", image_url: "/images/shoe-horn.jpg" },
  { id: 37, name: "Handtowels", price: 100, category: "Shoe Care", brand: "Monique", description: "Microfiber kitchen handtowels - long version. Multiple colors: blue, purple, yellow, red, green.", image_url: "/images/handtowels.jpg" },
  { id: 38, name: "Adidas Samba Black White", price: 3500, category: "Shoes", brand: "Adidas", description: "Adidas Samba Black White - classic sneakers. Sizes 40-45", image_url: "/images/samba.jpg" },
  { id: 39, name: "Nike Air Force 1 Undefeated Beige Navy", price: 3500, category: "Shoes", brand: "Nike", description: "Nike AF1 x Undefeated - beige, brown, navy, grey. Limited edition. Sizes 40-45", image_url: "/images/nike-af1-undefeated-beige.jpg" },
  { id: 40, name: "Nike Air Force 1 White Burgundy", price: 3500, category: "Shoes", brand: "Nike", description: "Nike AF1 Low white with burgundy sole. Premium leather. Sizes 40-45", image_url: "/images/nike-af1-white-burgundy.jpg" },
  { id: 41, name: "Nike Air Max 90 Surplus Grey", price: 3800, category: "Shoes", brand: "Nike", description: "Nike Air Max 90 Surplus grey with red accent. Sizes 40-45", image_url: "/images/nike-air-max-90-grey-surplus.jpg" },
  { id: 42, name: "Jordan 1 Low Travis Olive Brown", price: 4000, category: "Shoes", brand: "Jordan", description: "Jordan 1 Low x Travis style olive, beige, brown suede. Sizes 40-45", image_url: "/images/jordan-1-low-travis-olive.jpg" },
  { id: 43, name: "Nike Air Max Plus TN Black Volt", price: 4200, category: "Shoes", brand: "Nike", description: "Nike TN Air Max Plus black volt green. Sizes 40-45", image_url: "/images/nike-tn-black-volt.jpg" },
  { id: 44, name: "Nike Air Max Plus TN Black Blue", price: 4200, category: "Shoes", brand: "Nike", description: "Nike TN Air Max Plus black university blue. Sizes 40-45", image_url: "/images/nike-tn-black-blue.jpg" },
  { id: 45, name: "Converse All Star Low Brown Leather", price: 2500, category: "Shoes", brand: "Converse", description: "Converse Chuck Taylor All Star low brown leather. Sizes 40-45", image_url: "/images/converse-low-brown-leather.jpg" },
  { id: 46, name: "Nike Air Force 1 Triple Black", price: 3500, category: "Shoes", brand: "Nike", description: "Nike AF1 Low triple black. Classic. Sizes 40-45", image_url: "/images/nike-af1-triple-black.jpg" },
  { id: 47, name: "Converse Low Snakeskin Black", price: 2500, category: "Shoes", brand: "Converse", description: "Converse All Star low snakeskin black. Sizes 40-45", image_url: "/images/converse-low-snakeskin-black.jpg" },
  { id: 48, name: "Converse Low Snakeskin Maroon", price: 2500, category: "Shoes", brand: "Converse", description: "Converse All Star low snakeskin maroon. Sizes 40-45", image_url: "/images/converse-low-snakeskin-maroon.jpg" },
  { id: 49, name: "Nike AF1 Low x Chrome Hearts Olive White", price: 3800, category: "Shoes", brand: "Nike", description: "Chrome Hearts edition AF1 olive green/white with cross prints and charm. Sizes 40-45", image_url: "/images/nike-af1-chrome-hearts-olive.jpg" },
  { id: 50, name: "Nike AF1 Low White Silver Chrome Swoosh", price: 3500, category: "Shoes", brand: "Nike", description: "Nike AF1 triple white with liquid metal silver swoosh and chrome lace dubrae. Sizes 37-45", image_url: "/images/nike-af1-chrome-swoosh-white.jpg" },
  { id: 51, name: "Jordan 3 Retro Washed Denim Pink", price: 4500, category: "Shoes", brand: "Jordan", description: "Jordan 3 washed denim white/light blue with pink Jumpman. Sizes 40-45", image_url: "/images/jordan-3-washed-denim-pink.jpg" },
  { id: 52, name: "Vans Authentic Corduroy Black White", price: 2200, category: "Shoes", brand: "Vans", description: "Vans Authentic corduroy black with white sole and laces. Sizes 37-45", image_url: "/images/vans-corduroy-black-white.jpg" },
  { id: 53, name: "Vans Authentic Corduroy Triple Black", price: 2200, category: "Shoes", brand: "Vans", description: "Vans triple black corduroy. All black authentic. Sizes 37-45", image_url: "/images/vans-corduroy-triple-black.jpg" },
  { id: 54, name: "Nike AF1 Low Pink Beige Gold Charm", price: 3500, category: "Shoes", brand: "Nike", description: "Nike AF1 custom pink/beige/cream with gold chain pendant. Sizes 37-41", image_url: "/images/nike-af1-pink-beige-gold.jpg" },
  { id: 55, name: "Vans Authentic Corduroy Navy White", price: 2200, category: "Shoes", brand: "Vans", description: "Vans navy blue corduroy with white sole. Sizes 37-45", image_url: "/images/vans-corduroy-navy-white.jpg" },
  { id: 56, name: "Vans Authentic Corduroy Grey White", price: 2200, category: "Shoes", brand: "Vans", description: "Vans grey corduroy with white sole and laces. Sizes 37-45", image_url: "/images/vans-corduroy-grey-white.jpg" },
  { id: 57, name: "Vans Authentic Corduroy Black Grey Two-Tone", price: 2200, category: "Shoes", brand: "Vans", description: "Vans black/grey two-tone corduroy with black laces. Sizes 37-45", image_url: "/images/vans-corduroy-black-grey.jpg" },
  { id: 58, name: "Nike AF1 Low Wheat Mocha Black", price: 3500, category: "Shoes", brand: "Nike", description: "Nike AF1 wheat mocha brown/black with gum sole. Sizes 40-45", image_url: "/images/nike-af1-wheat-mocha.jpg" },
  { id: 59, name: "Nike AF1 Low Wheat Mocha Black", price: 3500, category: "Shoes", brand: "Nike", description: "AF1 wheat tan/black suede gum sole. Sizes 40-45", image_url: "/images/nike-af1-wheat-black-2.jpg" },
  { id: 60, name: "Nike AF1 Low x Supreme Gucci White Green", price: 3800, category: "Shoes", brand: "Nike", description: "Supreme Gucci edition white/green crackled leather. Sizes 37-45", image_url: "/images/nike-af1-supreme-gucci-green.jpg" },
  { id: 61, name: "New Balance 530 White Silver Navy", price: 3800, category: "Shoes", brand: "New Balance", description: "NB 530 white mesh silver/navy N logo. Sizes 37-45", image_url: "/images/nb-530-white-navy.jpg" },
  { id: 62, name: "Nike Air Max 90 Surplus Desert Beige", price: 4200, category: "Shoes", brand: "Nike", description: "Air Max 90 Surplus beige hemp orange swoosh. Sizes 40-45", image_url: "/images/airmax-90-surplus-beige.jpg" },
  { id: 63, name: "Nike Air Max 90 Surplus Cargo Khaki Volt", price: 4200, category: "Shoes", brand: "Nike", description: "Air Max 90 Surplus cargo khaki army green volt details. Sizes 40-45", image_url: "/images/airmax-90-surplus-khaki.jpg" },
  { id: 64, name: "Nike Air Max 90 Beige Black Orange", price: 4000, category: "Shoes", brand: "Nike", description: "Air Max 90 beige black with orange swoosh. Sizes 40-45", image_url: "/images/airmax-90-beige-black-orange.jpg" },
  { id: 65, name: "New Balance 530 White Black ABZORB", price: 3800, category: "Shoes", brand: "New Balance", description: "NB 530 white mesh black N ABZORB sole. Sizes 37-44", image_url: "/images/nb-530-white-black.jpg" },
  { id: 66, name: "Adidas Samba XLG Platform White Black Gum", price: 3800, category: "Shoes", brand: "Adidas", description: "Adidas Samba XLG platform white/black gum sole gold lettering. Sizes 37-44", image_url: "/images/adidas-samba-xlg-platform.jpg" },
  // --- 30 HOODS (Sweaters & Hoodies) ---
  { id: 67, name: "B Logo Black Sweater", price: 3500, category: "Hoods", brand: "Monique", description: "B Logo Black Sweater - premium knit Size M-XL", image_url: "/images/sweaters/b-logo-black.jpg" },
  { id: 68, name: "B Logo Dark Grey Sweater", price: 3500, category: "Hoods", brand: "Monique", description: "B Logo Dark Grey Sweater Size M-XL", image_url: "/images/sweaters/b-logo-dark-grey.jpg" },
  { id: 69, name: "B Logo Light Grey Tan Sweater", price: 3500, category: "Hoods", brand: "Monique", description: "B Logo Light Grey Tan Sweater Size M-XL", image_url: "/images/sweaters/b-logo-light-grey-tan.jpg" },
  { id: 70, name: "Black Floral Velvet Sweater", price: 4000, category: "Hoods", brand: "Monique", description: "Black Floral Velvet Sweater Size M-XL", image_url: "/images/sweaters/black-floral-velvet.jpg" },
  { id: 71, name: "Brown Marble Crew Sweater", price: 3800, category: "Hoods", brand: "Monique", description: "Brown Marble Crew Sweater Size M-XL", image_url: "/images/sweaters/brown-marble-crew.jpg" },
  { id: 72, name: "Charcoal Zip Sweater", price: 3800, category: "Hoods", brand: "Monique", description: "Charcoal Zip Sweater Size M-XL", image_url: "/images/sweaters/charcoal-zip.jpg" },
  { id: 73, name: "Cream Zip Sweater", price: 3500, category: "Hoods", brand: "Monique", description: "Cream Zip Sweater Size M-XL", image_url: "/images/sweaters/cream-zip.jpg" },
  { id: 74, name: "Light Grey Zip Sweater", price: 3500, category: "Hoods", brand: "Monique", description: "Light Grey Zip Sweater Size M-XL", image_url: "/images/sweaters/light-grey-zip.jpg" },
  { id: 75, name: "Navy Zip Sweater", price: 3500, category: "Hoods", brand: "Monique", description: "Navy Zip Sweater Size M-XL", image_url: "/images/sweaters/navy-zip.jpg" },
  { id: 76, name: "Off White Zip Sweater", price: 3500, category: "Hoods", brand: "Monique", description: "Off White Zip Sweater Size M-XL", image_url: "/images/sweaters/off-white-zip.jpg" },
  { id: 77, name: "Black White Striped Polo Sweater", price: 3500, category: "Hoods", brand: "Monique", description: "Black/white striped polo collar sweater - thick knit Size M-XL", image_url: "/images/sweaters/polo-striped-bw.jpg" },
  { id: 78, name: "Cream Quarter-Zip Sweater", price: 3800, category: "Hoods", brand: "Monique", description: "Cream quarter-zip fleece sweater Size M-XL", image_url: "/images/sweaters/quarter-cream-lolo.jpg" },
  { id: 79, name: "White Quarter-Zip Sweater", price: 3500, category: "Hoods", brand: "Monique", description: "White minimal quarter-zip sweater Size M-XL", image_url: "/images/sweaters/quarter-white-minimal.jpg" },
  { id: 80, name: "Sage Green Quarter-Zip Sweater", price: 3800, category: "Hoods", brand: "Monique", description: "Sage green quarter-zip sweater Size M-XL", image_url: "/images/sweaters/quarter-sage.jpg" },
  { id: 81, name: "Heather Light Grey Quarter-Zip", price: 3500, category: "Hoods", brand: "Monique", description: "Heather light grey quarter-zip with 3-line logo Size M-XL", image_url: "/images/sweaters/quarter-heather-light.jpg" },
  { id: 82, name: "Grey Undefeated Quarter-Zip", price: 3800, category: "Hoods", brand: "Monique", description: "Grey quarter-zip with embroidered logo Size M-XL", image_url: "/images/sweaters/quarter-grey-undef.jpg" },
  { id: 83, name: "Beige 3-Line Quarter-Zip Sweater", price: 3500, category: "Hoods", brand: "Monique", description: "Beige 3-line quarter-zip sweater Size M-XL", image_url: "/images/sweaters/quarter-beige-line.jpg" },
  { id: 84, name: "Cream Undefeated Quarter-Zip", price: 3800, category: "Hoods", brand: "Monique", description: "Cream quarter-zip with embroidered logo Size M-XL", image_url: "/images/sweaters/quarter-cream-undef.jpg" },
  { id: 85, name: "Black Oversized Hoodie", price: 4000, category: "Hoods", brand: "Monique", description: "Black oversized hoodie with kangaroo pocket Size M-XL", image_url: "/images/sweaters/hoodie-black.jpg" },
  { id: 86, name: "Cream Oversized Hoodie", price: 4000, category: "Hoods", brand: "Monique", description: "Cream oversized hoodie with kangaroo pocket Size M-XL", image_url: "/images/sweaters/hoodie-cream.jpg" },
  { id: 87, name: "Navy Pullover Hoodie", price: 3800, category: "Hoods", brand: "Monique", description: "Navy blue pullover hoodie with kangaroo pocket Size M-XL", image_url: "/images/sweaters/navy-pullover-hoodie.jpg" },
  { id: 88, name: "Grey Pullover Hoodie", price: 3800, category: "Hoods", brand: "Monique", description: "Light grey pullover hoodie Size M-XL", image_url: "/images/sweaters/grey-pullover-hoodie.jpg" },
  { id: 89, name: "Navy Zip-Up Hoodie", price: 4000, category: "Hoods", brand: "Monique", description: "Navy blue zip-up hoodie Size M-XL", image_url: "/images/sweaters/navy-zip-hoodie.jpg" },
  { id: 90, name: "Grey Zip-Up Hoodie", price: 4000, category: "Hoods", brand: "Monique", description: "Grey zip-up hoodie Size M-XL", image_url: "/images/sweaters/grey-zip-hoodie.jpg" },
  { id: 91, name: "Cream Zip-Up Hoodie", price: 4000, category: "Hoods", brand: "Monique", description: "Cream zip-up hoodie Size M-XL", image_url: "/images/sweaters/cream-zip-hoodie.jpg" },
  { id: 92, name: "Light Heather Zip Hoodie", price: 4000, category: "Hoods", brand: "Monique", description: "Light heather zip-up hoodie Size M-XL", image_url: "/images/sweaters/light-heather-zip-hoodie.jpg" },
  { id: 93, name: "Charcoal Zip-Up Hoodie", price: 4000, category: "Hoods", brand: "Monique", description: "Charcoal grey zip-up hoodie Size M-XL", image_url: "/images/sweaters/charcoal-zip-hoodie.jpg" },
  { id: 94, name: "Olive Paint Splatter Quarter-Zip", price: 3800, category: "Hoods", brand: "Monique", description: "Olive quarter-zip with paint splatter Size M-XL", image_url: "/images/sweaters/olive-paint-quarter.jpg" },
  { id: 95, name: "Milano Grey Zip Knit Cardigan", price: 4500, category: "Hoods", brand: "Monique", description: "Grey Milano knit zip cardigan with pattern Size M-XL", image_url: "/images/sweaters/milano-grey-zip-knit.jpg" },
  { id: 96, name: "White Cable Knit Sweater", price: 3500, category: "Hoods", brand: "Monique", description: "White textured cable knit sweater Size L", image_url: "/images/sweaters/white-cable-knit.jpg" },
  // --- 10 POLO SHIRTS ---
  { id: 97, name: "Black Polo Shirt Triangle Logo", price: 2500, category: "Polo Shirts", brand: "Monique", description: "Black polo with side buttons and triangle logo Size M-XXL", image_url: "/images/sweaters/polo-black-triangle.jpg" },
  { id: 98, name: "Sage Green Polo Triangle Logo", price: 2500, category: "Polo Shirts", brand: "Monique", description: "Sage green polo triangle logo Size M-XXL", image_url: "/images/sweaters/polo-sage-triangle.jpg" },
  { id: 99, name: "Dark Grey Polo Triangle Logo", price: 2500, category: "Polo Shirts", brand: "Monique", description: "Dark grey polo triangle logo Size M-XXL", image_url: "/images/sweaters/polo-darkgrey-triangle.jpg" },
  { id: 100, name: "White Striped Polo With Pocket", price: 2800, category: "Polo Shirts", brand: "Monique", description: "White striped polo with chest pocket Size M-XXL", image_url: "/images/sweaters/polo-white-striped-pocket.jpg" },
  { id: 101, name: "White Brown Color Block Polo", price: 2800, category: "Polo Shirts", brand: "Monique", description: "White/brown color block textured polo Size M-XXL", image_url: "/images/sweaters/polo-white-brown-block.jpg" },
  { id: 102, name: "Orange Grey Color Block Polo", price: 2800, category: "Polo Shirts", brand: "Monique", description: "Orange/grey color block textured polo Size M-XXL", image_url: "/images/sweaters/polo-orange-grey-block.jpg" },
  { id: 103, name: "Navy Blue CK Polo", price: 2500, category: "Polo Shirts", brand: "Monique", description: "Navy blue polo with embossed logo Size M-XXL", image_url: "/images/sweaters/polo-navy-ck.jpg" },
  { id: 104, name: "Charcoal Grey CK Polo", price: 2500, category: "Polo Shirts", brand: "Monique", description: "Charcoal grey polo with embossed logo Size M-XXL", image_url: "/images/sweaters/polo-charcoal-ck.jpg" },
  { id: 105, name: "White L Huang J Polo", price: 2500, category: "Polo Shirts", brand: "Monique", description: "White polo with small logo Size M-XXL", image_url: "/images/sweaters/polo-white-lhuang-1.jpg" },
  { id: 106, name: "White L Huang J Polo Classic", price: 2500, category: "Polo Shirts", brand: "Monique", description: "White classic fit polo Size M-XXL", image_url: "/images/sweaters/polo-white-lhuang-2.jpg" },
  { id: 107, name: "Black Trendsbar Polo Shirt", price: 2500, category: "Polo Shirts", brand: "Monique", description: "Black polo with small logo Size M-XXL", image_url: "/images/sweaters/polo-black-trendsbar.jpg" },
  { id: 108, name: "Off-White Trendsbar Polo Shirt", price: 2500, category: "Polo Shirts", brand: "Monique", description: "Off-white polo with small logo Size M-XXL", image_url: "/images/sweaters/polo-offwhite-trendsbar.jpg" },
  { id: 109, name: "White CK Polo Shirt", price: 2500, category: "Polo Shirts", brand: "Monique", description: "White textured CK polo Size M-XXL", image_url: "/images/sweaters/polo-white-ck-2.jpg" },
  { id: 110, name: "Black CK Polo Shirt", price: 2500, category: "Polo Shirts", brand: "Monique", description: "Black textured CK polo Size M-XXL", image_url: "/images/sweaters/polo-black-ck-2.jpg" },
  { id: 111, name: "Taupe Brown Striped Polo With Pocket", price: 2800, category: "Polo Shirts", brand: "Monique", description: "Taupe/brown/white striped polo with pocket Size M-XXL", image_url: "/images/sweaters/polo-taupe-brown-striped.jpg" },
  { id: 112, name: "Beige White Striped Polo With Pocket", price: 2800, category: "Polo Shirts", brand: "Monique", description: "Beige/white striped polo with pocket Size M-XXL", image_url: "/images/sweaters/polo-beige-white-striped.jpg" },
  { id: 113, name: "Black Grey White Striped Polo With Pocket", price: 2800, category: "Polo Shirts", brand: "Monique", description: "Black/grey/white striped polo with pocket Size M-XXL", image_url: "/images/sweaters/polo-black-grey-striped.jpg" },
  { id: 114, name: "Brown Zip Polo Shirt", price: 3000, category: "Polo Shirts", brand: "Monique", description: "Brown zip polo with logo Size M-XXL", image_url: "/images/sweaters/polo-brown-zip.jpg" },
  { id: 115, name: "Grey Zip Polo Shirt", price: 3000, category: "Polo Shirts", brand: "Monique", description: "Grey zip polo with logo Size M-XXL", image_url: "/images/sweaters/polo-grey-zip.jpg" },
  { id: 116, name: "Beige Zip Polo Shirt", price: 3000, category: "Polo Shirts", brand: "Monique", description: "Beige zip polo with logo Size M-XXL", image_url: "/images/sweaters/polo-beige-zip.jpg" }
];

export default function Home() {
  const [searchParams] = useSearchParams()
  const searchQuery = searchParams.get('search') || ''
  const categoryQuery = searchParams.get('category') || 'All'

  const [products, setProducts] = useState(HARDCODED_PRODUCTS)
  const [loading, setLoading] = useState(false)
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
        setLoading(true)
        const data = await getProducts()
        if (data?.products && data.products.length > 0) {
          const hardcodedNames = new Set(HARDCODED_PRODUCTS.map(p => p.name))
          const backendOnly = data.products.filter(p => !hardcodedNames.has(p.name) && (p.image_url || p.image) )
          const merged = [...HARDCODED_PRODUCTS, ...backendOnly.map(p => ({
            ...p,
            image_url: p.image_url || p.image || p.imageUrl
          })).filter(p => p.image_url && !p.image_url.includes('/uploads/') && p.image_url !== null)]
          setProducts(merged)
        } else {
          setProducts(HARDCODED_PRODUCTS)
        }
      } catch (err) {
        console.log('Using hardcoded products, backend offline:', err.message)
        setProducts(HARDCODED_PRODUCTS)
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
    const matchesSearch = !searchLower ||
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
    setSelectedBrands(prev => prev.includes(brand) ? prev.filter(b => b !== brand) : [...prev, brand])
  }
  const resetFilters = () => {
    setSearch(''); setMinPrice(''); setMaxPrice(''); setSelectedBrands([]); setActiveCategory('All')
  }

  if (loading) return (
    <div className="min-h-screen bg-[#f5f5f7] flex items-center justify-center">
      <div className="text-gray-500 text-lg">Loading products...</div>
    </div>
  )

  return (
    <div className="min-h-screen bg-[#f5f5f7] w-full overflow-x-hidden">
      <div className="w-full max-w-7xl mx-auto">
        <div className="page-header">
          <h1>Monique Investments</h1>
          <div className="page-header-row">
            <h2>{activeCategory === 'All' ? 'All Products' : activeCategory}</h2>
            <span className="product-count">{filteredProducts.length} products {products.length >= 106 ? `(${products.length} total)` : ''}</span>
          </div>
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-[320px_1fr] gap-4 md:gap-8 w-full">
          <aside className="hidden lg:block h-fit lg:sticky lg:top-24">
            <Filters search={search} setSearch={setSearch} minPrice={minPrice} setMinPrice={setMinPrice} maxPrice={maxPrice} setMaxPrice={setMaxPrice} selectedBrands={selectedBrands} toggleBrand={toggleBrand} allBrands={allBrands} resetFilters={resetFilters} />
          </aside>

          <div className="flex flex-col gap-4 sm:gap-6 w-full min-w-0">
            <div className="flex items-center justify-end gap-2 lg:hidden px-3">
              <button onClick={() => setShowFilters(true)} className="px-3 py-2 bg-white border border-gray-200 text-gray-800 rounded-lg hover:bg-gray-50 transition-colors text-sm min-h-11">Filters</button>
            </div>
            <CategoryFilter activeCategory={activeCategory} onSelect={setActiveCategory} />
            <div className="products-grid">
              {filteredProducts.length === 0 ? (
                <div className="col-span-full text-center text-gray-500 py-16">
                  <p className="text-base sm:text-lg mb-4">{search ? `No products found for "${search}"` : 'No products found. Try adjusting filters.'}</p>
                  <button onClick={resetFilters} className="px-4 py-2 text-sm text-[#e93a0e] hover:underline font-medium min-h-11">Clear filters</button>
                </div>
              ) : filteredProducts.map(product => (
                <ProductCard key={product.id || product._id} product={product} />
              ))}
            </div>
          </div>
        </div>
      </div>

      {showFilters && (
        <div className="lg:hidden fixed inset-0 z-50 bg-black/30 backdrop-blur-sm" onClick={() => setShowFilters(false)}>
          <div className="absolute right-0 top-0 h-full w-full max-w-sm p-4" onClick={e => e.stopPropagation()}>
            <Filters search={search} setSearch={setSearch} minPrice={minPrice} setMinPrice={setMinPrice} maxPrice={maxPrice} setMaxPrice={setMaxPrice} selectedBrands={selectedBrands} toggleBrand={toggleBrand} allBrands={allBrands} resetFilters={resetFilters} onClose={() => setShowFilters(false)} />
          </div>
        </div>
      )}
    </div>
  )
}
