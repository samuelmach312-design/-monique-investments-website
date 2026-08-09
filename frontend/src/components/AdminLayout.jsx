import { useState, useEffect, useMemo } from 'react';
import axios from 'axios';

export default function AdminLayout() {
  const API = 'http://localhost:3001/api/mongo-products';
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState('');
  const [cat, setCat] = useState('All');
  const [showModal, setShowModal] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState({ name:'', brand:'Monique', category:'Shoes', size:'42', sellingPrice:'', stock:'10', image:'', description:'' });

  const load = async () => {
    try {
      setLoading(true);
      const r = await axios.get(API);
      setProducts(Array.isArray(r.data)? r.data : r.data.products || []);
    }
    catch(e){ console.error(e) } finally { setLoading(false) }
  };
  useEffect(()=>{ load() },[]);

  const stats = useMemo(()=>{
    const totalValue = products.reduce((s,p)=> s + (p.sellingPrice||p.price||0)*(p.stock||0), 0);
    const low = products.filter(p=> p.stock < 5).length;
    return { count: products.length, value: totalValue, low, brands: new Set(products.map(p=>p.brand)).size }
  },[products]);

  const filtered = products.filter(p=>{
    const matchQ = (p.name + p.brand + p.category).toLowerCase().includes(q.toLowerCase());
    const matchCat = cat==='All' || p.category===cat || p.brand===cat;
    return matchQ && matchCat;
  });

  const openAdd = () => { setEditing(null); setForm({ name:'', brand:'Monique', category:'Shoes', size:'42', sellingPrice:'', stock:'10', image:'', description:'' }); setShowModal(true); };
  const openEdit = (p) => { setEditing(p._id); setForm({ name:p.name, brand:p.brand, category:p.category||'Shoes', size:p.size, sellingPrice:p.sellingPrice||p.price, stock:p.stock, image:p.image, description:p.description||'' }); setShowModal(true); };

  const submit = async (e) => {
    e.preventDefault();
    const payload = { name:form.name, brand:form.brand, category:form.category, size:form.size, sellingPrice:Number(form.sellingPrice), price:Number(form.sellingPrice), stock:Number(form.stock), image:form.image||'https://images.unsplash.com/photo-1542291026-7eec264c27ff', description:form.description };
    try {
      if(editing) await axios.put(API + '/' + editing, payload);
      else await axios.post(API, payload);
      setShowModal(false); load();
    } catch(err){ alert(err.response?.data?.error || err.message) }
  };
  const del = async (id) => { if(!confirm('Delete product permanently?')) return; await axios.delete(API + '/'+id); load(); };

  return (
    <div className="min-h-screen bg-[#f8f9fb] flex font-[Inter]">
      {/* SIDEBAR */}
      <div className="w- bg-[#0a0a0a] text-white p-7 flex flex-col fixed h-full">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-white text-black rounded-xl flex items-center justify-center font-black">M</div>
          <div><div className="font-black leading-none">MONIQUE</div><div className="text-xs tracking-[0.3em] opacity-60">INVESTMENTS</div></div>
        </div>
        <div className="mt-10 space-y-2 text-sm">
          <div className="bg-white text-black px-4 py-3 rounded-xl font-bold flex justify-between">Products <span className="bg-black text-white px-2 rounded-full text-xs">{products.length}</span></div>
          <a href="/" className="px-4 py-3 rounded-xl block opacity-60 hover:bg-white/10">← Back to Store</a>
          <div className="px-4 py-3 rounded-xl opacity-40 text-xs mt-6">API: localhost:3001/api</div>
        </div>
        <div className="mt-auto bg-white/5 p-4 rounded-2xl">
          <div className="text-xs opacity-60">Total Inventory Value</div>
          <div className="text-xl font-black mt-1">KSh {stats.value.toLocaleString()}</div>
          <div className="text-xs mt-2 text-green-400">{stats.low} low stock alerts</div>
        </div>
      </div>

      {/* MAIN */}
      <div className="ml- flex-1 p-8">
        <div className="flex justify-between items-center">
          <div><h1 className="text-3xl font-black tracking-tight">Inventory</h1><p className="text-gray-500 text-sm mt-1">Manage your products, stock and pricing</p></div>
          <button onClick={openAdd} className="bg-black text-white px-6 py-3 rounded-full font-bold text-sm hover:bg-zinc-800">+ Add Product</button>
        </div>

        {/* STATS */}
        <div className="grid grid-cols-4 gap-4 mt-8">
          <div className="bg-white p-5 rounded-2xl border"><div className="text-xs text-gray-400 uppercase tracking-widest">Total Products</div><div className="text-3xl font-black mt-2">{stats.count}</div><div className="text-xs text-green-600 mt-2">✓ Live in store</div></div>
          <div className="bg-white p-5 rounded-2xl border"><div className="text-xs text-gray-400 uppercase tracking-widest">Brands</div><div className="text-3xl font-black mt-2">{stats.brands}</div><div className="text-xs text-gray-500 mt-2">Monique, Nike, Adidas...</div></div>
          <div className="bg-white p-5 rounded-2xl border"><div className="text-xs text-gray-400 uppercase tracking-widest">Low Stock</div><div className="text-3xl font-black mt-2 text-amber-600">{stats.low}</div><div className="text-xs text-amber-600 mt-2">Need restock</div></div>
          <div className="bg-black text-white p-5 rounded-2xl"><div className="text-xs opacity-60 uppercase tracking-widest">Inventory Value</div><div className="text-3xl font-black mt-2">KSh {(stats.value/1000).toFixed(0)}k</div><div className="text-xs opacity-60 mt-2">Retail value</div></div>
        </div>

        {/* FILTERS */}
        <div className="bg-white mt-6 p-3 rounded-2xl border flex gap-3 items-center">
          <input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search products, brand, category..." className="flex-1 bg-[#f5f5f7] px-4 py-3 rounded-xl text-sm outline-none" />
          <select value={cat} onChange={e=>setCat(e.target.value)} className="bg-[#f5f5f7] px-4 py-3 rounded-xl text-sm">
            <option>All</option><option>Shoes</option><option>Boots</option><option>Slides</option><option>Monique</option><option>Nike</option><option>Adidas</option>
          </select>
          <button onClick={load} className="px-5 py-3 rounded-xl bg-black text-white text-sm font-bold">{loading? '...' : 'Refresh'}</button>
        </div>

        {/* TABLE */}
        <div className="bg-white mt-4 rounded-2xl border overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-[#fcfcfc] text-xs tracking-widest uppercase text-gray-400"><tr><th className="text-left p-4 pl-6">Product</th><th>Category</th><th>Size</th><th>Price</th><th>Stock</th><th className="text-right pr-6">Actions</th></tr></thead>
            <tbody>
              {filtered.map(p=>(
                <tr key={p._id} className="border-t hover:bg-gray-50/80 group">
                  <td className="p-3 pl-6 flex items-center gap-3"><img src={p.image} className="w-14 h-14 rounded-xl object-cover bg-gray-100"/><div><div className="font-bold">{p.name}</div><div className="text-xs text-gray-400">{p.brand} • ID {p._id.slice(-6)}</div></div></td>
                  <td className="text-center"><span className="bg-gray-100 px-3 py-1 rounded-full text-xs">{p.category}</span></td>
                  <td className="text-center font-medium">{p.size}</td>
                  <td className="text-center font-black">KSh {(p.sellingPrice||p.price||0).toLocaleString()}</td>
                  <td className="text-center"><span className={`px-3 py-1 rounded-full text-xs font-bold ${p.stock<5? 'bg-amber-100 text-amber-700' : 'bg-green-100 text-green-700'}`}>{p.stock} in stock</span></td>
                  <td className="text-right pr-6"><button onClick={()=>openEdit(p)} className="text-xs bg-black text-white px-3 py-1.5 rounded-full mr-2">Edit</button><button onClick={()=>del(p._id)} className="text-xs bg-red-50 text-red-600 px-3 py-1.5 rounded-full">Delete</button></td>
                </tr>
              ))}
            </tbody>
          </table>
          {filtered.length===0 && <div className="p-16 text-center text-gray-400">{loading?'Loading products...':'No products found'}</div>}
        </div>
      </div>

      {/* MODAL */}
      {showModal && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-6">
          <form onSubmit={submit} className="bg-white w-full max-w-lg rounded-2xl p-8">
            <div className="flex justify-between items-center"><h2 className="text-xl font-black">{editing?'Edit Product':'New Product'}</h2><button type="button" onClick={()=>setShowModal(false)} className="w-8 h-8 bg-gray-100 rounded-full">✕</button></div>
            <div className="grid grid-cols-2 gap-3 mt-6">
              <input value={form.name} onChange={e=>setForm({...form,name:e.target.value})} placeholder="Product name" className="col-span-2 border p-3.5 rounded-xl text-sm" required />
              <input value={form.brand} onChange={e=>setForm({...form,brand:e.target.value})} placeholder="Brand" className="border p-3.5 rounded-xl text-sm" />
              <select value={form.category} onChange={e=>setForm({...form,category:e.target.value})} className="border p-3.5 rounded-xl text-sm"><option>Shoes</option><option>Boots</option><option>Slides</option><option>Accessories</option><option>Shoe Care</option></select>
              <input value={form.size} onChange={e=>setForm({...form,size:e.target.value})} placeholder="Size 42 / 40-45" className="border p-3.5 rounded-xl text-sm" />
              <input value={form.sellingPrice} onChange={e=>setForm({...form,sellingPrice:e.target.value})} placeholder="Price KSh" type="number" className="border p-3.5 rounded-xl text-sm" required />
              <input value={form.stock} onChange={e=>setForm({...form,stock:e.target.value})} placeholder="Stock" type="number" className="border p-3.5 rounded-xl text-sm col-span-2" />
              <input value={form.image} onChange={e=>setForm({...form,image:e.target.value})} placeholder="Image URL" className="col-span-2 border p-3.5 rounded-xl text-sm" />
              {form.image && <img src={form.image} className="col-span-2 h-32 w-full object-cover rounded-xl" />}
              <textarea value={form.description} onChange={e=>setForm({...form,description:e.target.value})} placeholder="Description (optional)" className="col-span-2 border p-3.5 rounded-xl text-sm h-20" />
              <button className="col-span-2 bg-black text-white py-4 rounded-xl font-bold mt-2">{editing?'Update Product':'Create Product'}</button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}