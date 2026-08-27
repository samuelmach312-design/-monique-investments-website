import { useState, useEffect } from 'react';
import axios from 'axios';
const BASE = (import.meta.env.VITE_API_URL || 'http://localhost:3001/api').replace(/\/$/, '');
const API = BASE + '/mongo-products';
const FALLBACK = '/images/monique-logo.png';

export default function AdminLayout(){
  const [products,setProducts]=useState([]);
  const [auth,setAuth]=useState(null);
  const [phone,setPhone]=useState('');
  const [search,setSearch]=useState('');
  const [view,setView]=useState('table');
  const ALLOWED={'254706631292':'Samuel','254723808067':'Monicah'};
  const norm=(p)=>{let x=p.replace(/\D/g,'');if(x.startsWith('0'))x='254'+x.slice(1);if(x.startsWith('7'))x='254'+x;return x;};
  useEffect(()=>{const s=localStorage.getItem('monique_admin');if(s){try{setAuth(JSON.parse(s))}catch{}}},[]);
  const fetchProducts=async()=>{try{const r=await axios.get(API);setProducts(r.data.products||r.data||[])}catch{}};
  useEffect(()=>{if(auth)fetchProducts()},[auth]);
  const filtered=products.filter(p=>(p.name+' '+(p.brand||'')).toLowerCase().includes(search.toLowerCase()));
  const totalValue=products.reduce((s,p)=>s+(Number(p.sellingPrice||p.price||0)*Number(p.stock||1)),0);

  if(!auth)return(<div className="min-h-screen bg-black flex items-center justify-center p-4"><div className="bg-white p-10 rounded- w-full max-w-sm"><h1 className="font-black text-3xl text-center">MONIQUE</h1><input value={phone} onChange={e=>setPhone(e.target.value)} placeholder="0706 631 292" className="w-full border-2 p-4 rounded-2xl mt-8 font-bold"/><button onClick={()=>{const a=ALLOWED[norm(phone)];if(a){const d={name:a,phone:norm(phone)};localStorage.setItem('monique_admin',JSON.stringify(d));setAuth(d)}else alert('Unauthorized')}} className="w-full bg-black text-[#D4AF37] py-4 rounded-2xl mt-4 font-black">ENTER →</button></div></div>);

  return(
    <div className="min-h-screen bg-[#fcfaf5]">
      <div className="bg-black text-white sticky top-0 z-50 px-6 py-4 flex justify-between items-center">
        <div className="font-black text-">MONIQUE INVENTORY - {auth.name} • {products.length} Products • KSh {totalValue.toLocaleString()}</div>
        <div className="flex gap-2"><button onClick={()=>setView(view==='table'?'grid':'table')} className="bg-white/10 px-4 py-2 rounded-full text- font-bold">{view==='table'?'Grid View':'Table View'}</button><button onClick={()=>{localStorage.removeItem('monique_admin');setAuth(null)}} className="bg-[#D4AF37] text-black px-4 py-2 rounded-full text- font-black">Logout</button></div>
      </div>
      <div className="max-w- mx-auto p-6">
        <input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search products..." className="w-full bg-white border rounded-full px-6 py-3 mb-6 outline-none font-bold"/>
        {view==='table'?(
          <div className="bg-white rounded-2xl border overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-">
                <thead className="bg-black text-[#D4AF37] text- tracking-widest"><tr><th className="p-4 text-left">IMG</th><th className="p-4 text-left">NAME</th><th className="p-4">BRAND</th><th className="p-4">SIZE</th><th className="p-4">BUY</th><th className="p-4">SELL</th><th className="p-4">PROFIT</th><th className="p-4">STOCK</th><th className="p-4">ACTION</th></tr></thead>
                <tbody>{filtered.map(p=><tr key={p._id} className="border-t hover:bg-[#fcfaf5]"><td className="p-3"><img src={p.image||p.image_url||FALLBACK} onError={e=>{e.target.onerror=null; e.target.src=FALLBACK}} className="w-12 h-12 object-contain bg-[#fcfaf5] rounded-xl p-1"/></td><td className="p-3 font-bold max-w- truncate">{p.name}</td><td className="p-3 text-center">{p.brand}</td><td className="p-3 text-center">{p.size}</td><td className="p-3 text-center text-gray-500">{p.buyingPrice||0}</td><td className="p-3 text-center font-black">KSh {p.sellingPrice||p.price}</td><td className="p-3 text-center"><span className="bg-green-50 text-green-700 px-2 py-1 rounded-full text- font-bold">{(p.sellingPrice||0)-(p.buyingPrice||0)}</span></td><td className="p-3 text-center">{p.stock}</td><td className="p-3 flex gap-1"><button onClick={async()=>{if(confirm('Delete?')){await axios.delete(API+'/'+p._id);fetchProducts()}}} className="bg-red-50 text-red-600 px-3 py-1 rounded-full text- font-bold">Del</button></td></tr>)}</tbody>
              </table>
            </div>
          </div>
        ):(
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">{filtered.map(p=><div key={p._id} className="bg-white rounded-2xl border p-3"><img src={p.image||p.image_url||FALLBACK} onError={e=>{e.target.onerror=null; e.target.src=FALLBACK}} className="w-full aspect-square object-contain bg-[#fcfaf5] rounded-xl p-2"/><div className="font-bold text- mt-2 truncate">{p.name}</div><div className="font-black text-">KSh {p.sellingPrice||p.price}</div></div>)}</div>
        )}
      </div>
    </div>
  )
}