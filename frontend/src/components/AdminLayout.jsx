import { useState, useEffect } from 'react';
import axios from 'axios';

const BASE = (import.meta.env.VITE_API_URL || 'http://localhost:3001/api').replace(/\/$/, '');
const API = BASE + '/mongo-products';

export default function AdminLayout(){
  const [products,setProducts] = useState([]);
  const [auth,setAuth] = useState(null);
  const [phone,setPhone] = useState('');
  const [search,setSearch] = useState('');
  const [filterBrand,setFilterBrand] = useState('All');
  const [showAdd,setShowAdd] = useState(false);
  const [editing,setEditing] = useState(null);
  const [form,setForm] = useState({ name:'', brand:'', category:'Sneakers', buyingPrice:'', sellingPrice:'', stock:'', size:'', color:'', image:'' });
  const [loading,setLoading] = useState(false);

  const ALLOWED = { '254706631292': 'Samuel', '254723808067': 'Monicah' };
  const norm = (p)=>{let x=p.replace(/\D/g,''); if(x.startsWith('0')) x='254'+x.slice(1); if(x.startsWith('7')) x='254'+x; return x;};

  useEffect(()=>{
    const saved = localStorage.getItem('monique_admin');
    if(saved){
      try{ setAuth(JSON.parse(saved)); }catch{}
    }
  },[]);

  const fetchProducts = async()=>{
    setLoading(true);
    try{ const r=await axios.get(API); setProducts(r.data.products || r.data || []); }catch(e){ console.error(e); }finally{setLoading(false);}
  };
  useEffect(()=>{ if(auth) fetchProducts(); },[auth]);

  const brands = ['All',...new Set(products.map(p=>p.brand).filter(Boolean))];
  const filtered = products.filter(p=>{
    const mSearch = (p.name+' '+p.brand).toLowerCase().includes(search.toLowerCase());
    const mBrand = filterBrand==='All' || p.brand===filterBrand;
    return mSearch && mBrand;
  });

  const totalValue = products.reduce((s,p)=>s+(Number(p.sellingPrice||p.price||0)*Number(p.stock||1)),0);
  const totalProfit = products.reduce((s,p)=>s+((Number(p.sellingPrice||0)-Number(p.buyingPrice||0))*Number(p.stock||1)),0);

  const handleSave = async()=>{
    if(!form.name ||!form.sellingPrice) return alert('Name & Price required');
    setLoading(true);
    try{
      const payload = {...form, price: Number(form.sellingPrice), sellingPrice: Number(form.sellingPrice), buyingPrice: Number(form.buyingPrice||0), stock: Number(form.stock||0), image_url: form.image };
      if(editing){ await axios.put(API+'/'+editing._id, payload); }
      else{ await axios.post(API, payload); }
      setShowAdd(false); setEditing(null); setForm({ name:'', brand:'', category:'Sneakers', buyingPrice:'', sellingPrice:'', stock:'', size:'', color:'', image:'' });
      fetchProducts();
    }catch(e){ alert(e.response?.data?.message||'Error'); }finally{setLoading(false);}
  };

  const handleDelete = async(id)=>{ if(!confirm('Delete?')) return; await axios.delete(API+'/'+id); fetchProducts(); };

  if(!auth){
    return (
      <div className="min-h-screen bg-[#0a0a0a] flex items-center justify-center p-4">
        <div className="bg-white p-10 rounded- w-full max-w-sm shadow-2xl">
          <h1 className="font-black text-3xl text-center">MONIQUE</h1><p className="text-center text-xs tracking-[0.3em] text-[#D4AF37] font-bold">ADMIN ACCESS</p>
          <input value={phone} onChange={e=>setPhone(e.target.value)} placeholder="0706 631 292" className="w-full border-2 p-4 rounded-2xl mt-8 font-bold" />
          <button onClick={()=>{ const a=ALLOWED[norm(phone)]; if(a){const d={name:a,phone:norm(phone)}; localStorage.setItem('monique_admin',JSON.stringify(d)); setAuth(d);} else alert('Only Samuel & Monicah');}} className="w-full bg-black text-[#D4AF37] py-4 rounded-2xl mt-4 font-black">ENTER →</button>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-[#fcfaf5] text-black">
      <div className="bg-black text-white sticky top-0 z-50 border-b border-[#D4AF37]/30">
        <div className="max-w- mx-auto px-6 py-4 flex justify-between items-center">
          <div className="flex items-center gap-3"><div className="w-10 h-10 bg-[#D4AF37] rounded-xl flex items-center justify-center font-black text-black">M</div><div><div className="font-black leading-none">MONIQUE INVENTORY - {auth.name}</div><div className="text- text-[#D4AF37] font-bold">GOLD EDITION</div></div></div>
          <div className="flex gap-2"><button onClick={()=>setShowAdd(true)} className="bg-[#D4AF37] text-black px-6 py-2.5 rounded-full font-black text-sm">+ ADD</button><button onClick={()=>{localStorage.removeItem('monique_admin'); setAuth(null);}} className="bg-white/10 px-5 py-2.5 rounded-full text-xs font-bold">Logout</button></div>
        </div>
      </div>
      <div className="max-w- mx-auto p-6">
        <div className="grid grid-cols-3 gap-4 mb-6"><div className="bg-black text-white rounded-2xl p-5"><div className="text-[#D4AF37] text-xs font-bold">PRODUCTS</div><div className="text-3xl font-black">{products.length}</div></div><div className="bg-white rounded-2xl p-5 border"><div className="text-gray-400 text-xs font-bold">VALUE</div><div className="text-2xl font-black">KSh {totalValue.toLocaleString()}</div></div><div className="bg-[#D4AF37] rounded-2xl p-5"><div className="text-black/60 text-xs font-bold">PROFIT</div><div className="text-2xl font-black">KSh {totalProfit.toLocaleString()}</div></div></div>
        <div className="bg-white rounded-2xl p-3 border flex gap-3 mb-6"><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search..." className="flex-1 bg-[#fcfaf5] rounded-full px-5 py-2.5 outline-none" /><div className="flex gap-2">{brands.map(b=><button key={b} onClick={()=>setFilterBrand(b)} className={`px-4 py-2 rounded-full text-xs font-black ${filterBrand===b?'bg-black text-[#D4AF37]':'bg-[#fcfaf5]'}`}>{b}</button>)}</div></div>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">{filtered.map(p=><div key={p._id} className="bg-white rounded-2xl border overflow-hidden"><div className="aspect-square bg-[#fcfaf5]"><img src={p.image||p.image_url} className="w-full h-full object-cover" /></div><div className="p-3"><div className="font-black text-sm truncate">{p.name}</div><div className="text- text-gray-400">{p.brand} • {p.size}</div><div className="font-black mt-1">KSh {p.sellingPrice||p.price}</div><div className="flex gap-2 mt-2"><button onClick={()=>{setEditing(p); setForm({...p, sellingPrice:p.sellingPrice||p.price, image:p.image||p.image_url}); setShowAdd(true);}} className="flex-1 bg-black text-white py-1.5 rounded-full text-xs font-bold">Edit</button><button onClick={()=>handleDelete(p._id)} className="flex-1 bg-red-50 text-red-600 py-1.5 rounded-full text-xs font-bold">Del</button></div></div></div>)}</div>
        {filtered.length===0 &&!loading && <div className="text-center py-20 bg-white rounded-2xl border border-dashed">No products - API: {API}</div>}
      </div>
      {showAdd && <div className="fixed inset-0 bg-black/80 z-[100] flex items-center justify-center p-4"><div className="bg-white rounded- w-full max-w-lg p-6 max-h- overflow-y-auto"><h2 className="font-black text-xl mb-4">{editing?'EDIT':'ADD'} PRODUCT</h2><div className="space-y-3"><input value={form.name} onChange={e=>setForm({...form,name:e.target.value})} placeholder="Name" className="w-full bg-[#fcfaf5] p-3 rounded-xl font-bold" /><div className="grid grid-cols-2 gap-2"><input value={form.brand} onChange={e=>setForm({...form,brand:e.target.value})} placeholder="Brand" className="bg-[#fcfaf5] p-3 rounded-xl" /><input value={form.category} onChange={e=>setForm({...form,category:e.target.value})} placeholder="Category" className="bg-[#fcfaf5] p-3 rounded-xl" /></div><div className="grid grid-cols-2 gap-2"><input value={form.buyingPrice} onChange={e=>setForm({...form,buyingPrice:e.target.value})} type="number" placeholder="Buying" className="bg-[#fcfaf5] p-3 rounded-xl" /><input value={form.sellingPrice} onChange={e=>setForm({...form,sellingPrice:e.target.value})} type="number" placeholder="Selling" className="bg-[#fcfaf5] p-3 rounded-xl border-2 border-[#D4AF37]/30" /></div><div className="grid grid-cols-3 gap-2"><input value={form.stock} onChange={e=>setForm({...form,stock:e.target.value})} placeholder="Stock" className="bg-[#fcfaf5] p-3 rounded-xl" /><input value={form.size} onChange={e=>setForm({...form,size:e.target.value})} placeholder="Size" className="bg-[#fcfaf5] p-3 rounded-xl" /><input value={form.color} onChange={e=>setForm({...form,color:e.target.value})} placeholder="Color" className="bg-[#fcfaf5] p-3 rounded-xl" /></div><input value={form.image} onChange={e=>setForm({...form,image:e.target.value})} placeholder="Image URL" className="w-full bg-[#fcfaf5] p-3 rounded-xl" />{form.image && <img src={form.image} className="w-full h-32 object-cover rounded-xl" />}</div><button onClick={handleSave} className="w-full bg-black text-[#D4AF37] py-3 rounded-xl mt-4 font-black">{editing?'UPDATE':'ADD'}</button><button onClick={()=>{setShowAdd(false); setEditing(null);}} className="w-full mt-2 py-2 text-sm">Cancel</button></div></div>}
    </div>
  )
}