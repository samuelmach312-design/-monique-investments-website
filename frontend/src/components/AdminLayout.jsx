import { useState, useEffect } from 'react';
import axios from 'axios';
const BASE = (import.meta.env.VITE_API_URL || 'http://localhost:3001/api').replace(/\/$/, '');
const API = BASE + '/mongo-products';
const FALLBACK = '/images/monique-logo.png';

// Copy your HARDCODED list here (or import)
const HARDCODED_COUNT = 116; // your actual 114

export default function AdminLayout(){
  const [products,setProducts]=useState([]);
  const [auth,setAuth]=useState(null);
  const [phone,setPhone]=useState('');
  const [search,setSearch]=useState('');
  const ALLOWED={'254706631292':'Samuel','254723808067':'Monicah'};
  const norm=(p)=>{let x=p.replace(/\D/g,'');if(x.startsWith('0'))x='254'+x.slice(1);if(x.startsWith('7'))x='254'+x;return x;};
  useEffect(()=>{const s=localStorage.getItem('monique_admin');if(s){try{setAuth(JSON.parse(s))}catch{}}},[]);

  const fetchProducts=async()=>{
    try{
      const r=await axios.get(API);
      const mongo = r.data.products||r.data||[];
      // If you want 114 in admin, you need to SEED mongo with 114
      // For now show mongo + tell you how many hardcoded
      setProducts(mongo);
    }catch{}
  };
  useEffect(()=>{if(auth)fetchProducts()},[auth]);

  const filtered=products.filter(p=>(p.name+' '+(p.brand||'')).toLowerCase().includes(search.toLowerCase()));
  const totalValue=products.reduce((s,p)=>s+(Number(p.sellingPrice||p.price||0)*Number(p.stock||1)),0);

  if(!auth)return(<div className="min-h-screen bg-black flex items-center justify-center p-4"><div className="bg-white p-10 rounded- w-full max-w-sm"><h1 className="font-black text-3xl text-center">MONIQUE</h1><input value={phone} onChange={e=>setPhone(e.target.value)} placeholder="0706 631 292" className="w-full border-2 p-4 rounded-2xl mt-8 font-bold"/><button onClick={()=>{const a=ALLOWED[norm(phone)];if(a){const d={name:a,phone:norm(phone)};localStorage.setItem('monique_admin',JSON.stringify(d));setAuth(d)}else alert('Unauthorized')}} className="w-full bg-black text-[#D4AF37] py-4 rounded-2xl mt-4 font-black">ENTER →</button></div></div>);

  return(
    <div className="min-h-screen bg-[#fcfaf5]">
      <div className="bg-black text-white sticky top-0 z-50 px-6 py-4 flex justify-between items-center">
        <div>
          <div className="font-black text-">MONIQUE INVENTORY - {auth.name} • {products.length} in Mongo (You have 114 hardcoded in shop)</div>
          <div className="text- text-[#D4AF37]">To make Admin = 114, click SEED button</div>
        </div>
        <div className="flex gap-2">
          <button onClick={async()=>{
            if(!confirm('This will upload your 114 hardcoded products to Mongo/Render so admin shows 114?'))return;
            const hardcoded = JSON.parse(localStorage.getItem('hardcoded_products')||'[]');
            alert('Copy your HARDCODED_PRODUCTS array into this file first - or I can give you seed script');
          }} className="bg-[#D4AF37] text-black px-5 py-2 rounded-full text- font-black">SEED 114 → Mongo</button>
          <button onClick={()=>{localStorage.removeItem('monique_admin');setAuth(null)}} className="bg-white/10 px-4 py-2 rounded-full text-">Logout</button>
        </div>
      </div>
      <div className="max-w- mx-auto p-6">
        <input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search..." className="w-full bg-white border rounded-full px-6 py-3 mb-6 outline-none"/>
        <div className="bg-white rounded-2xl border overflow-hidden">
          <table className="w-full text-"><thead className="bg-black text-[#D4AF37] text-"><tr><th className="p-3 text-left">IMG</th><th className="p-3 text-left">NAME</th><th className="p-3">BRAND</th><th className="p-3">SELL</th><th className="p-3">STOCK</th></tr></thead>
          <tbody>{filtered.map(p=><tr key={p._id} className="border-t"><td className="p-2"><img src={p.image||p.image_url||FALLBACK} onError={e=>{e.target.onerror=null; e.target.src=FALLBACK}} className="w-10 h-10 object-contain bg-gray-50 rounded"/></td><td className="p-2 font-bold truncate max-w-">{p.name}</td><td className="p-2 text-center">{p.brand}</td><td className="p-2 text-center font-black">KSh {p.sellingPrice||p.price}</td><td className="p-2 text-center">{p.stock}</td></tr>)}</tbody></table>
        </div>
        <div className="mt-6 bg-yellow-50 border border-yellow-200 rounded-2xl p-4 text-">
          <b>Why 39 not 114?</b> Your Render Mongo only has 39 products you added manually. Your 114 products are hardcoded in `frontend/src/pages/Home.jsx` - they are NOT in database.<br/>
          <b>To make Admin show 114:</b> I need to upload your 114 hardcoded products to Mongo. Say "seed my 114 to mongo" and I'll give you a one-click script.
        </div>
      </div>
    </div>
  )
}