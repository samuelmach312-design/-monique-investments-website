import { useState, useEffect } from 'react';
import axios from 'axios';

const API = (import.meta.env.VITE_API_URL || 'http://localhost:3001') + '/api/mongo-products';

export default function AdminLayout(){
  const [products,setProducts] = useState([]);
  const [auth,setAuth] = useState(localStorage.getItem('monique_admin')? JSON.parse(localStorage.getItem('monique_admin')) : null);
  const [phone,setPhone] = useState('');

  const ALLOWED = { '254706631292': 'Samuel', '254723808067': 'Monicah' };
  const norm = (p)=>{let x=p.replace(/\D/g,''); if(x.startsWith('0')) x='254'+x.slice(1); if(x.startsWith('7')) x='254'+x; return x;};

  useEffect(()=>{ if(auth) axios.get(API).then(r=>setProducts(r.data.products || r.data || [])).catch(()=>{}); },[auth]);

  if(!auth){
    return (
      <div className="min-h-screen bg-black flex items-center justify-center p-4">
        <div className="bg-white p-8 rounded-2xl w-full max-w-sm">
          <h1 className="font-black text-2xl text-center">MONIQUE ADMIN</h1>
          <input value={phone} onChange={e=>setPhone(e.target.value)} placeholder="0706631292" className="w-full border p-3 rounded-xl mt-6" />
          <button onClick={()=>{ const a=ALLOWED[norm(phone)]; if(a){const d={name:a,phone:norm(phone)}; localStorage.setItem('monique_admin',JSON.stringify(d)); setAuth(d);} else alert('Only Samuel & Monicah');}} className="w-full bg-black text-[#D4AF37] py-3 rounded-xl mt-3 font-bold">Login</button>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-[#fcfaf5] p-6">
      <div className="max-w-6xl mx-auto">
        <div className="flex justify-between items-center">
          <h1 className="text-3xl font-black">MONIQUE INVENTORY - {auth.name}</h1>
          <button onClick={()=>{localStorage.removeItem('monique_admin'); setAuth(null);}} className="text-sm bg-red-100 text-red-600 px-4 py-2 rounded-full">Logout</button>
        </div>
        <div className="mt-6 bg-white rounded-2xl border p-4">
          <div className="font-bold">Products: {products.length}</div>
          <div className="mt-4 grid grid-cols-2 md:grid-cols-4 gap-3">
            {products.map(p=>(
              <div key={p._id} className="border p-3 rounded-xl">
                <img src={p.image || p.image_url} className="w-full h-24 object-cover rounded-lg bg-gray-100" />
                <div className="font-bold text-sm mt-2">{p.name}</div>
                <div className="text-xs text-gray-500">{p.brand} - KSh {p.sellingPrice||p.price}</div>
              </div>
            ))}
          </div>
          {products.length===0 && <div className="text-center py-20 text-gray-400">No products yet - API: {API}</div>}
        </div>
      </div>
    </div>
  )
}