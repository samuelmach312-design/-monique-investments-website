import { useState, useEffect } from 'react';
import axios from 'axios';

const BASE = (import.meta.env.VITE_API_URL || 'http://localhost:3001/api').replace(/\/$/, '');
const API = `${BASE}/mongo-products`;

export default function AdminLayout(){
  const [products,setProducts] = useState([]);
  const [auth,setAuth] = useState(()=>{ try{return JSON.parse(localStorage.getItem('monique_admin'))}catch{return null} }());
  const [phone,setPhone] = useState('');
  const [search,setSearch] = useState('');
  const [filterBrand,setFilterBrand] = useState('All');
  const [showAdd,setShowAdd] = useState(false);
  const [editing,setEditing] = useState(null);
  const [form,setForm] = useState({ name:'', brand:'', category:'Sneakers', buyingPrice:'', sellingPrice:'', stock:'', size:'', color:'', image:'', image_url:'' });
  const [loading,setLoading] = useState(false);

  const ALLOWED = { '254706631292': 'Samuel', '254723808067': 'Monicah' };
  const norm = (p)=>{let x=p.replace(/\D/g,''); if(x.startsWith('0')) x='254'+x.slice(1); if(x.startsWith('7')) x='254'+x; return x;};

  const fetchProducts = async()=>{
    setLoading(true);
    try{ const r=await axios.get(API); setProducts(r.data.products || r.data || []); }catch(e){ console.error(e); }finally{setLoading(false);}
  };
  useEffect(()=>{ if(auth) fetchProducts(); },[auth]);

  const brands = ['All',...new Set(products.map(p=>p.brand).filter(Boolean))];
  const filtered = products.filter(p=>{
    const mSearch = `${p.name} ${p.brand}`.toLowerCase().includes(search.toLowerCase());
    const mBrand = filterBrand==='All' || p.brand===filterBrand;
    return mSearch && mBrand;
  });

  const totalValue = products.reduce((s,p)=>s+(Number(p.sellingPrice||p.price||0)*Number(p.stock||1)),0);
  const totalProfit = products.reduce((s,p)=>s+((Number(p.sellingPrice||0)-Number(p.buyingPrice||0))*Number(p.stock||1)),0);

  const handleSave = async()=>{
    if(!form.name ||!form.sellingPrice) return alert('Name & Price required');
    setLoading(true);
    try{
      const payload = {...form, price: Number(form.sellingPrice), sellingPrice: Number(form.sellingPrice), buyingPrice: Number(form.buyingPrice||0), stock: Number(form.stock||0) };
      if(editing){ await axios.put(`${API}/${editing._id}`, payload); }
      else{ await axios.post(API, payload); }
      setShowAdd(false); setEditing(null); setForm({ name:'', brand:'', category:'Sneakers', buyingPrice:'', sellingPrice:'', stock:'', size:'', color:'', image:'', image_url:'' });
      fetchProducts();
    }catch(e){ alert(e.response?.data?.message||'Error saving'); }finally{setLoading(false);}
  };

  const handleDelete = async(id)=>{ if(!confirm('Delete this product?')) return; await axios.delete(`${API}/${id}`); fetchProducts(); };

  if(!auth){
    return (
      <div className="min-h-screen bg-[#0a0a0a] flex items-center justify-center p-4 relative overflow-hidden">
        <div className="absolute top-0 left-0 w- h- bg-[#D4AF37]/20 rounded-full blur- -translate-x-1/2 -translate-y-1/2" />
        <div className="bg-white/95 backdrop-blur p-10 rounded- w-full max-w-sm shadow-[0_20px_80px_rgba(212,175,55,0.3)] border border-[#D4AF37]/20">
          <div className="w-16 h-16 bg-black rounded-2xl flex items-center justify-center mx-auto mb-6 shadow-xl"><span className="text-[#D4AF37] font-black text-2xl">M</span></div>
          <h1 className="font-black text-3xl text-center tracking-tight">MONIQUE</h1><p className="text-center text-xs tracking-[0.3em] text-[#D4AF37] font-bold mt-1">ADMIN ACCESS</p>
          <input value={phone} onChange={e=>setPhone(e.target.value)} placeholder="0706 631 292" className="w-full border-2 border-black/10 p-4 rounded-2xl mt-8 focus:border-[#D4AF37] outline-none font-bold" />
          <button onClick={()=>{ const a=ALLOWED[norm(phone)]; if(a){const d={name:a,phone:norm(phone)}; localStorage.setItem('monique_admin',JSON.stringify(d)); setAuth(d);} else alert('Only Samuel & Monicah allowed');}} className="w-full bg-black text-[#D4AF37] py-4 rounded-2xl mt-4 font-black tracking-widest hover:bg-[#D4AF37] hover:text-black transition-all">ENTER VAULT →</button>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-[#fcfaf5] text-black">
      <div className="bg-black text-white sticky top-0 z-50 border-b border-[#D4AF37]/30">
        <div className="max-w- mx-auto px-6 py-4 flex justify-between items-center">
          <div className="flex items-center gap-4"><div className="w-10 h-10 bg-[#D4AF37] rounded-xl flex items-center justify-center font-black text-black">M</div><div><div className="font-black tracking-tight leading-none">MONIQUE INVENTORY</div><div className="text- tracking-[0.2em] text-[#D4AF37] font-bold">GOLD EDITION • {auth.name.toUpperCase()}</div></div></div>
          <div className="flex gap-2"><button onClick={()=>setShowAdd(true)} className="bg-[#D4AF37] text-black px-6 py-2.5 rounded-full font-black text-sm hover:scale-105 transition">+ ADD PRODUCT</button><button onClick={()=>{localStorage.removeItem('monique_admin'); setAuth(null);}} className="bg-white/10 px-5 py-2.5 rounded-full text-xs font-bold">Logout</button></div>
        </div>
      </div>

      <div className="max-w- mx-auto p-6">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
          <div className="bg-black text-white rounded-[1.5rem] p-6 relative overflow-hidden"><div className="absolute right-0 top-0 w-32 h-32 bg-[#D4AF37]/20 rounded-full blur-2xl" /><div className="text-[#D4AF37] text-xs font-bold tracking-widest">TOTAL PRODUCTS</div><div className="text-4xl font-black mt-2">{products.length}</div></div>
          <div className="bg-white rounded-[1.5rem] p-6 border shadow-sm"><div className="text-gray-400 text-xs font-bold tracking-widest">INVENTORY VALUE</div><div className="text-3xl font-black mt-2">KSh {totalValue.toLocaleString()}</div></div>
          <div className="bg-[#D4AF37] rounded-[1.5rem] p-6"><div className="text-black/60 text-xs font-bold tracking-widest">POTENTIAL PROFIT</div><div className="text-3xl font-black mt-2 text-black">KSh {totalProfit.toLocaleString()}</div></div>
        </div>

        <div className="bg-white rounded-[1.5rem] p-4 border flex flex-wrap gap-3 items-center mb-6">
          <input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search name, brand..." className="flex-1 min-w- bg-[#fcfaf5] border-0 rounded-full px-6 py-3 outline-none font-medium" />
          <div className="flex gap-2 overflow-x-auto">{brands.map(b=><button key={b} onClick={()=>setFilterBrand(b)} className={`px-5 py-2.5 rounded-full text-xs font-black whitespace-nowrap ${filterBrand===b?'bg-black text-[#D4AF37]':'bg-[#fcfaf5] hover:bg-black hover:text-white'}`}>{b}</button>)}</div>
        </div>

        {loading? <div className="text-center py-20 font-black tracking-widest animate-pulse">LOADING VAULT...</div> : (
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-4">
          {filtered.map(p=>{
            const profit = (Number(p.sellingPrice||p.price||0) - Number(p.buyingPrice||0));
            return (
            <div key={p._id} className="bg-white rounded-[1.5rem] border overflow-hidden group hover:shadow-[0_20px_60px_rgba(0,0,0,0.1)] hover:-translate-y-1 transition-all">
              <div className="aspect-square bg-[#fcfaf5] relative overflow-hidden"><img src={p.image || p.image_url} className="w-full h-full object-cover group-hover:scale-110 transition duration-700" /><div className="absolute top-3 left-3 bg-black text-[#D4AF37] text- font-black px-3 py-1 rounded-full">{p.brand}</div>{p.stock<=2 && <div className="absolute top-3 right-3 bg-red-500 text-white text- font-black px-2 py-1 rounded-full">LOW</div>}</div>
              <div className="p-4"><div className="font-black leading-tight truncate">{p.name}</div><div className="text- text-gray-400 font-bold mt-1">{p.category} • {p.size} • {p.color}</div><div className="flex justify-between items-end mt-3"><div><div className="text-xs text-gray-400 line-through">Buy {p.buyingPrice}</div><div className="font-black">KSh {(p.sellingPrice||p.price)?.toLocaleString()}</div></div><div className={`text- font-black px-2 py-1 rounded-full ${profit>0?'bg-green-100 text-green-700':'bg-gray-100'}`}>+{profit}</div></div><div className="grid grid-cols-2 gap-2 mt-3"><button onClick={()=>{setEditing(p); setForm({...p, buyingPrice:p.buyingPrice||'', sellingPrice:p.sellingPrice||p.price||''}); setShowAdd(true);}} className="bg-black text-white py-2 rounded-full text-xs font-bold">Edit</button><button onClick={()=>handleDelete(p._id)} className="bg-red-50 text-red-600 py-2 rounded-full text-xs font-bold">Del</button></div></div>
            </div>
          )})}
        </div>
        )}
        {filtered.length===0 &&!loading && <div className="text-center py-24 bg-white rounded- border border-dashed"><div className="text-6xl mb-4">👟</div><div className="font-black">No products found</div><div className="text-sm text-gray-400 mt-1">API: {API}</div><div className="text-xs text-gray-400 mt-2">Check Render: {BASE}</div></div>}
      </div>

      {showAdd && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur z-[100] flex items-center justify-center p-4">
          <div className="bg-white rounded- w-full max-w-lg p-8 max-h- overflow-y-auto">
            <div className="flex justify-between items-center mb-6"><h2 className="font-black text-2xl">{editing?'EDIT':'ADD'} PRODUCT</h2><button onClick={()=>{setShowAdd(false); setEditing(null);}} className="w-8 h-8 bg-black/5 rounded-full">✕</button></div>
            <div className="space-y-3">
              <input value={form.name} onChange={e=>setForm({...form,name:e.target.value})} placeholder="Product Name (e.g. Air Jordan 1)" className="w-full bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold" />
              <div className="grid grid-cols-2 gap-3"><input value={form.brand} onChange={e=>setForm({...form,brand:e.target.value})} placeholder="Brand (Nike)" className="bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold" /><input value={form.category} onChange={e=>setForm({...form,category:e.target.value})} placeholder="Category" className="bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold" /></div>
              <div className="grid grid-cols-2 gap-3"><input value={form.buyingPrice} onChange={e=>setForm({...form,buyingPrice:e.target.value})} type="number" placeholder="Buying Price" className="bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold" /><input value={form.sellingPrice} onChange={e=>setForm({...form,sellingPrice:e.target.value})} type="number" placeholder="Selling Price" className="bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold border-2 border-[#D4AF37]/30" /></div>
              <div className="grid grid-cols-3 gap-3"><input value={form.stock} onChange={e=>setForm({...form,stock:e.target.value})} type="number" placeholder="Stock" className="bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold" /><input value={form.size} onChange={e=>setForm({...form,size:e.target.value})} placeholder="Size 42" className="bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold" /><input value={form.color} onChange={e=>setForm({...form,color:e.target.value})} placeholder="Color" className="bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold" /></div>
              <input value={form.image||form.image_url} onChange={e=>setForm({...form,image:e.target.value,image_url:e.target.value})} placeholder="Image URL https://..." className="w-full bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold" />
              {form.image && <img src={form.image} className="w-full h-40 object-cover rounded-2xl" />}
            </div>
            <button onClick={handleSave} disabled={loading} className="w-full bg-black text-[#D4AF37] py-4 rounded-2xl mt-6 font-black tracking-widest hover:bg-[#D4AF37] hover:text-black transition">{loading?'SAVING...': editing?'UPDATE PRODUCT':'ADD TO VAULT'}</button>
          </div>
        </div>
      )}
    </div>
  )
}