import { useState, useEffect } from 'react';
import axios from 'axios';

const BASE = (import.meta.env.VITE_API_URL || 'http://localhost:3001/api').replace(/\/$/, '');
const API = BASE + '/mongo-products';
const PLACEHOLDER = 'https://via.placeholder.com/400x400/0a0a0a/D4AF37?text=M';

export default function AdminLayout(){
  const [products,setProducts] = useState([]);
  const [auth,setAuth] = useState(null);
  const [phone,setPhone] = useState('');
  const [search,setSearch] = useState('');
  const [filterBrand,setFilterBrand] = useState('All');
  const [showAdd,setShowAdd] = useState(false);
  const [editing,setEditing] = useState(null);
  const [form,setForm] = useState({ name:'', brand:'', category:'Sneakers', buyingPrice:'', sellingPrice:'', stock:'1', size:'40-45', color:'', image:'' });
  const [loading,setLoading] = useState(false);

  const ALLOWED = { '254706631292': 'Samuel', '254723808067': 'Monicah' };
  const norm = (p)=>{let x=p.replace(/\D/g,''); if(x.startsWith('0')) x='254'+x.slice(1); if(x.startsWith('7')) x='254'+x; return x;};

  useEffect(()=>{
    const saved = localStorage.getItem('monique_admin');
    if(saved){ try{ setAuth(JSON.parse(saved)); }catch{} }
  },[]);

  const fetchProducts = async()=>{
    setLoading(true);
    try{ const r=await axios.get(API); setProducts(r.data.products || r.data || []); }catch(e){ console.error(e); }finally{setLoading(false);}
  };
  useEffect(()=>{ if(auth) fetchProducts(); },[auth]);

  const brands = ['All',...new Set(products.map(p=>p.brand).filter(Boolean))];
  const filtered = products.filter(p=>{
    const mSearch = (p.name+' '+p.brand+' '+p.category).toLowerCase().includes(search.toLowerCase());
    const mBrand = filterBrand==='All' || p.brand===filterBrand;
    return mSearch && mBrand;
  });

  const totalValue = products.reduce((s,p)=>s+(Number(p.sellingPrice||p.price||0)*Number(p.stock||1)),0);

  const handleSave = async()=>{
    if(!form.name ||!form.sellingPrice) return alert('Name & Selling Price required');
    setLoading(true);
    try{
      const payload = {
        name: form.name, brand: form.brand, category: form.category,
        buyingPrice: Number(form.buyingPrice||0),
        sellingPrice: Number(form.sellingPrice), price: Number(form.sellingPrice),
        stock: Number(form.stock||1), size: form.size, color: form.color,
        image: form.image, image_url: form.image
      };
      if(editing){ await axios.put(API+'/'+editing._id, payload); }
      else{ await axios.post(API, payload); }
      setShowAdd(false); setEditing(null);
      setForm({ name:'', brand:'', category:'Sneakers', buyingPrice:'', sellingPrice:'', stock:'1', size:'40-45', color:'', image:'' });
      fetchProducts();
    }catch(e){ alert('Error saving - check Render logs'); }finally{setLoading(false);}
  };

  const handleDelete = async(id)=>{ if(!confirm('Delete permanently?')) return; await axios.delete(API+'/'+id); fetchProducts(); };

  const getImg = (p)=> p.image || p.image_url || PLACEHOLDER;

  if(!auth){
    return (
      <div className="min-h-screen bg-[#0a0a0a] flex items-center justify-center p-4">
        <div className="bg-white p-10 rounded- w-full max-w-sm">
          <h1 className="font-black text-3xl text-center">MONIQUE</h1><p className="text-center text-xs tracking-[0.3em] text-[#D4AF37] font-bold">ADMIN VAULT</p>
          <input value={phone} onChange={e=>setPhone(e.target.value)} placeholder="0706 631 292" className="w-full border-2 p-4 rounded-2xl mt-8 font-bold" />
          <button onClick={()=>{ const a=ALLOWED[norm(phone)]; if(a){const d={name:a,phone:norm(phone)}; localStorage.setItem('monique_admin',JSON.stringify(d)); setAuth(d);} else alert('Unauthorized');}} className="w-full bg-black text-[#D4AF37] py-4 rounded-2xl mt-4 font-black">ENTER →</button>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-[#fcfaf5] text-black">
      <div className="bg-black text-white sticky top-0 z-50 border-b border-[#D4AF37]/30">
        <div className="max-w- mx-auto px-6 py-4 flex justify-between items-center">
          <div className="flex items-center gap-3"><div className="w-10 h-10 bg-[#D4AF37] rounded-xl flex items-center justify-center font-black text-black">M</div><div><div className="font-black leading-none">MONIQUE INVENTORY - {auth.name}</div><div className="text- text-[#D4AF37] font-bold">39 PRODUCTS • GOLD EDITION</div></div></div>
          <div className="flex gap-2"><button onClick={()=>{setEditing(null); setForm({ name:'', brand:'', category:'Sneakers', buyingPrice:'', sellingPrice:'', stock:'1', size:'40-45', color:'', image:'' }); setShowAdd(true);}} className="bg-[#D4AF37] text-black px-6 py-2.5 rounded-full font-black text-sm hover:scale-105 transition">+ ADD PRODUCT</button><button onClick={()=>{localStorage.removeItem('monique_admin'); setAuth(null);}} className="bg-white/10 px-5 py-2.5 rounded-full text-xs font-bold">Logout</button></div>
        </div>
      </div>

      <div className="max-w- mx-auto p-6">
        <div className="grid grid-cols-3 gap-4 mb-6">
          <div className="bg-black text-white rounded-2xl p-6"><div className="text-[#D4AF37] text-xs font-bold tracking-widest">PRODUCTS</div><div className="text-4xl font-black mt-1">{products.length}</div><div className="text-xs opacity-60 mt-1">Live from Render</div></div>
          <div className="bg-white rounded-2xl p-6 border"><div className="text-gray-400 text-xs font-bold tracking-widest">INVENTORY VALUE</div><div className="text-3xl font-black mt-1">KSh {totalValue.toLocaleString()}</div></div>
          <div className="bg-white rounded-2xl p-6 border"><div className="text-gray-400 text-xs font-bold tracking-widest">API STATUS</div><div className="text-sm font-black mt-1 text-green-600">● Connected</div><div className="text- text-gray-400 truncate mt-1">{BASE}</div></div>
        </div>

        <div className="bg-white rounded-2xl p-3 border flex flex-wrap gap-3 mb-6">
          <input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search shoes, belts..." className="flex-1 min-w- bg-[#fcfaf5] rounded-full px-6 py-3 outline-none font-medium" />
          <div className="flex gap-2 overflow-x-auto">{brands.map(b=><button key={b} onClick={()=>setFilterBrand(b)} className={`px-5 py-2.5 rounded-full text-xs font-black whitespace-nowrap transition ${filterBrand===b?'bg-black text-[#D4AF37]':'bg-[#fcfaf5] hover:bg-black hover:text-white'}`}>{b}</button>)}</div>
        </div>

        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-5">
          {filtered.map(p=>{
            const img = getImg(p);
            return (
            <div key={p._id} className="bg-white rounded-[1.5rem] border overflow-hidden group hover:shadow-[0_20px_60px_rgba(0,0,0,0.12)] hover:-translate-y-1 transition-all duration-300">
              <div className="aspect-square bg-[#fcfaf5] relative overflow-hidden">
                <img src={img} alt={p.name} onError={(e)=>e.target.src=PLACEHOLDER} className="w-full h-full object-cover group-hover:scale-110 transition duration-700" />
                <div className="absolute top-3 left-3 bg-black/90 backdrop-blur text-[#D4AF37] text- font-black px-3 py-1 rounded-full">{p.brand||'Monique'}</div>
                <div className="absolute bottom-3 left-3 bg-white/90 backdrop-blur text-black text- font-bold px-2.5 py-1 rounded-full">{p.stock} in stock</div>
              </div>
              <div className="p-4">
                <div className="font-black text-sm leading-tight truncate">{p.name}</div>
                <div className="text- text-gray-500 font-medium mt-1">{p.category} • {p.size} {p.color && `• ${p.color}`}</div>
                <div className="flex justify-between items-center mt-3">
                  <div className="font-black text-lg">KSh {(p.sellingPrice||p.price)?.toLocaleString()}</div>
                  {Number(p.buyingPrice)>0 && <div className="text- bg-green-50 text-green-700 font-bold px-2 py-1 rounded-full">Profit {(p.sellingPrice||0)-(p.buyingPrice||0)}</div>}
                </div>
                <div className="grid grid-cols-2 gap-2 mt-3">
                  <button onClick={()=>{setEditing(p); setForm({ name:p.name, brand:p.brand||'', category:p.category||'Sneakers', buyingPrice:p.buyingPrice||'', sellingPrice:p.sellingPrice||p.price||'', stock:p.stock||1, size:p.size||'40-45', color:p.color||'', image: p.image||p.image_url||'' }); setShowAdd(true);}} className="bg-black text-white py-2.5 rounded-full text-xs font-black hover:bg-[#D4AF37] hover:text-black transition">Edit</button>
                  <button onClick={()=>handleDelete(p._id)} className="bg-gray-100 text-gray-600 py-2.5 rounded-full text-xs font-bold hover:bg-red-50 hover:text-red-600 transition">Delete</button>
                </div>
              </div>
            </div>
          )})}
        </div>
      </div>

      {showAdd && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-md z-[100] flex items-center justify-center p-4">
          <div className="bg-white rounded- w-full max-w-lg p-8 max-h- overflow-y-auto shadow-2xl">
            <div className="flex justify-between items-center mb-6"><h2 className="font-black text-2xl tracking-tight">{editing?'EDIT PRODUCT':'ADD NEW PRODUCT'}</h2><button onClick={()=>{setShowAdd(false); setEditing(null);}} className="w-9 h-9 bg-black/5 rounded-full font-bold">✕</button></div>
            <div className="space-y-4">
              <div><label className="text- font-black tracking-widest text-gray-400">PRODUCT NAME</label><input value={form.name} onChange={e=>setForm({...form,name:e.target.value})} placeholder="Nike Air Max 90" className="w-full bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold mt-1 focus:ring-2 focus:ring-[#D4AF37]" /></div>
              <div className="grid grid-cols-2 gap-3"><div><label className="text- font-black tracking-widest text-gray-400">BRAND</label><input value={form.brand} onChange={e=>setForm({...form,brand:e.target.value})} placeholder="Nike" className="w-full bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold mt-1" /></div><div><label className="text- font-black tracking-widest text-gray-400">CATEGORY</label><select value={form.category} onChange={e=>setForm({...form,category:e.target.value})} className="w-full bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold mt-1"><option>Sneakers</option><option>Boots</option><option>Official</option><option>Accessories</option><option>Belts</option></select></div></div>
              <div className="grid grid-cols-2 gap-3"><div><label className="text- font-black tracking-widest text-gray-400">BUYING PRICE</label><input value={form.buyingPrice} onChange={e=>setForm({...form,buyingPrice:e.target.value})} type="number" placeholder="2500" className="w-full bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold mt-1" /></div><div><label className="text- font-black tracking-widest text-[#D4AF37]">SELLING PRICE *</label><input value={form.sellingPrice} onChange={e=>setForm({...form,sellingPrice:e.target.value})} type="number" placeholder="4000" className="w-full bg-[#fcfaf5] p-4 rounded-2xl outline-none font-black mt-1 border-2 border-[#D4AF37]/30" /></div></div>
              <div className="grid grid-cols-3 gap-3"><input value={form.stock} onChange={e=>setForm({...form,stock:e.target.value})} type="number" placeholder="Stock" className="bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold" /><input value={form.size} onChange={e=>setForm({...form,size:e.target.value})} placeholder="Size 40-45" className="bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold" /><input value={form.color} onChange={e=>setForm({...form,color:e.target.value})} placeholder="Color" className="bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold" /></div>
              <div><label className="text- font-black tracking-widest text-gray-400">IMAGE URL (Paste direct link)</label><input value={form.image} onChange={e=>setForm({...form,image:e.target.value})} placeholder="https://images.unsplash.com/..." className="w-full bg-[#fcfaf5] p-4 rounded-2xl outline-none font-bold mt-1" /><div className="text- text-gray-400 mt-1">Tip: Right-click any shoe image → Copy image address</div>{form.image && <img src={form.image} onError={(e)=>e.target.src=PLACEHOLDER} className="w-full h-48 object-cover rounded-2xl mt-3 border" />}</div>
            </div>
            <button onClick={handleSave} disabled={loading} className="w-full bg-black text-[#D4AF37] py-4 rounded-2xl mt-8 font-black tracking-widest hover:bg-[#D4AF37] hover:text-black transition text-sm">{loading?'SAVING TO VAULT...': editing?'UPDATE PRODUCT':'ADD TO INVENTORY →'}</button>
          </div>
        </div>
      )}
    </div>
  )
}