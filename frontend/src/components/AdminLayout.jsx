import { useState, useEffect, useMemo } from 'react';
import axios from 'axios';

const API = '/api/mongo-products';

const ALLOWED_ADMINS = {
  '254706631292': { name: 'Samuel', phone: '0706631292', role: 'Owner', initial: 'S' },
  '254723808067': { name: 'Monicah', phone: '0723808067', role: 'Admin', initial: 'M' },
};

function normalizePhone(phone) {
  let p = phone.replace(/\s+/g, '').replace('+', '');
  if (p.startsWith('0')) p = '254' + p.slice(1);
  if (p.startsWith('7') && p.length === 9) p = '254' + p;
  return p;
}

// FIXED IMAGE HANDLER FOR LIVE
const getImageUrl = (p) => {
  if (!p) return '';
  if (p.image) return p.image;
  if (!p.image_url) return '';
  if (p.image_url.startsWith('http')) return p.image_url;
  return p.image_url; // already /uploads/...
};

export default function AdminLayout() {
  const [auth, setAuth] = useState(() => {
    const saved = localStorage.getItem('monique_admin');
    return saved? JSON.parse(saved) : null;
  });
  const [loginPhone, setLoginPhone] = useState('');
  const [loginError, setLoginError] = useState('');
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [q, setQ] = useState('');
  const [cat, setCat] = useState('All');
  const [showModal, setShowModal] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState({ name:'', brand:'Monique', category:'Shoes', size:'42', sellingPrice:'', stock:'10', image:'', description:'' });

  const getAdminHeaders = () => {
    const adminPhone = auth?.phone || '0706631292';
    return { headers: { 'x-admin-phone': adminPhone } };
  };

  const handleLogin = (e) => {
    e.preventDefault();
    const normalized = normalizePhone(loginPhone);
    const admin = ALLOWED_ADMINS[normalized];
    if (admin) {
      setAuth(admin);
      localStorage.setItem('monique_admin', JSON.stringify(admin));
      setLoginError('');
    } else {
      setLoginError('Access denied. Only Samuel (0706631292) and Monicah (0723808067) are allowed.');
    }
  };

  const handleLogout = () => {
    localStorage.removeItem('monique_admin');
    setAuth(null);
  };

  const load = async () => {
    try {
      setLoading(true);
      const r = await axios.get(API, getAdminHeaders());
      setProducts(Array.isArray(r.data)? r.data : r.data.products || []);
    } catch(e){
      console.error(e);
      if(e.response?.status === 403) handleLogout();
    } finally { setLoading(false) }
  };

  useEffect(()=>{ if(auth) load() },[auth]);

  const stats = useMemo(()=>{
    const totalValue = products.reduce((s,p)=> s + (Number(p.sellingPrice||p.price||0))*(Number(p.stock||0)), 0);
    const low = products.filter(p=> Number(p.stock) < 5).length;
    return { count: products.length, value: totalValue, low, brands: new Set(products.map(p=>p.brand)).size }
  },[products]);

  const filtered = products.filter(p=>{
    const matchQ = (p.name + p.brand + p.category).toLowerCase().includes(q.toLowerCase());
    const matchCat = cat==='All' || p.category===cat || p.brand===cat;
    return matchQ && matchCat;
  });

  const openAdd = () => { setEditing(null); setForm({ name:'', brand:'Monique', category:'Shoes', size:'42', sellingPrice:'', stock:'10', image:'', description:'' }); setShowModal(true); };

  const openEdit = (p) => {
    setEditing(p._id || p.id);
    setForm({
      name:p.name,
      brand:p.brand,
      category:p.category||'Shoes',
      size:p.size || p.sizes,
      sellingPrice:p.sellingPrice||p.price,
      stock:p.stock,
      image: getImageUrl(p),
      description:p.description||''
    });
    setShowModal(true);
  };

  const submit = async (e) => {
    e.preventDefault();
    const payload = {
      name:form.name, brand:form.brand, category:form.category, size:form.size,
      sellingPrice:Number(form.sellingPrice), price:Number(form.sellingPrice),
      stock:Number(form.stock),
      image:form.image||'https://images.unsplash.com/photo-1542291026-7eec264c27ff',
      description:form.description
    };
    try {
      if(editing) await axios.put(API + '/' + editing, payload, getAdminHeaders());
      else await axios.post(API, payload, getAdminHeaders());
      setShowModal(false);
      load();
    } catch(err){ alert(err.response?.data?.error || err.message) }
  };

  const del = async (id) => {
    if(!confirm('Delete product permanently?')) return;
    try {
      await axios.delete(API + '/' + id, getAdminHeaders());
      load();
    } catch(err){ alert(err.response?.data?.error || err.message) }
  };

  if (!auth) {
    return (
      <div className="min-h-screen bg-[#0a0a0a] flex items-center justify-center p-4">
        <div className="bg-white w-full max-w-sm rounded-2xl p-8 shadow-2xl">
          <div className="w-12 h-12 bg-black text-white rounded-xl flex items-center justify-center font-black text-xl mx-auto">M</div>
          <h1 className="text-center font-black text-2xl mt-4">MONIQUE</h1>
          <p className="text-center text-xs tracking-[0.3em] opacity-50">ADMIN ACCESS</p>
          <form onSubmit={handleLogin} className="mt-6">
            <input value={loginPhone} onChange={e=>setLoginPhone(e.target.value)} placeholder="0706631292" className="w-full border p-4 rounded-xl mt-2 text-sm outline-none focus:border-black" required />
            {loginError && <div className="mt-3 text-xs bg-red-50 text-red-600 p-3 rounded-xl">{loginError}</div>}
            <button className="w-full bg-black text-white py-4 rounded-xl font-bold mt-4">Login Securely</button>
          </form>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[#f8f9fb] flex">
      <div className="w- bg-[#0a0a0a] text-white p-7 flex flex-col fixed h-full z-10">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 bg-white text-black rounded-xl flex items-center justify-center font-black">M</div>
          <div><div className="font-black">MONIQUE</div><div className="text-xs tracking-[0.3em] opacity-60">INVESTMENTS</div></div>
        </div>
        <div className="mt-10 space-y-2 text-sm">
          <div className="bg-white text-black px-4 py-3 rounded-xl font-bold flex justify-between">Products <span className="bg-black text-white px-2 rounded-full text-xs">{products.length}</span></div>
          <a href="/" className="px-4 py-3 rounded-xl block opacity-60 hover:bg-white/10">← Back to Store</a>
        </div>
        <div className="mt-auto space-y-3">
          <div className="bg-white/5 p-4 rounded-2xl">
            <div className="text-xs opacity-60">Total Inventory Value</div>
            <div className="text-xl font-black mt-1">KSh {stats.value.toLocaleString()}</div>
            <div className="text-xs mt-2 text-amber-400">{stats.low} low stock</div>
          </div>
          <div className="bg-white/10 p-3 rounded-2xl flex items-center gap-3">
            <div className="w-9 h-9 bg-white text-black rounded-full flex items-center justify-center font-black">{auth.initial}</div>
            <div className="flex-1"><div className="text-sm font-bold">{auth.name}</div><div className="text-xs opacity-60">{auth.phone}</div></div>
            <button onClick={handleLogout} className="text-xs bg-red-500/20 text-red-300 px-3 py-1.5 rounded-full">Logout</button>
          </div>
        </div>
      </div>

      <div className="ml- flex-1 p-8">
        <div className="flex justify-between items-center">
          <div><h1 className="text-3xl font-black">Inventory</h1><p className="text-gray-500 text-sm mt-1">Logged in as <span className="font-bold text-black">{auth.name}</span></p></div>
          <button onClick={openAdd} className="bg-black text-white px-6 py-3 rounded-full font-bold text-sm">+ Add Product</button>
        </div>
        <div className="bg-white mt-6 p-3 rounded-2xl border flex gap-3">
          <input value={q} onChange={e=>setQ(e.target.value)} placeholder="Search..." className="flex-1 bg-[#f5f5f7] px-4 py-3 rounded-xl text-sm outline-none" />
          <button onClick={load} className="px-5 py-3 rounded-xl bg-black text-white text-sm font-bold">{loading? '...' : 'Refresh'}</button>
        </div>
        <div className="bg-white mt-4 rounded-2xl border overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-[#fcfcfc] text-xs uppercase text-gray-400"><tr><th className="text-left p-4 pl-6">Product</th><th className="text-right pr-6">Actions</th></tr></thead>
            <tbody>
              {filtered.map(p=>(
                <tr key={p._id || p.id} className="border-t">
                  <td className="p-3 pl-6 flex items-center gap-3">
                    <img src={getImageUrl(p)} className="w-14 h-14 rounded-xl object-cover bg-gray-100"/>
                    <div><div className="font-bold">{p.name}</div><div className="text-xs text-gray-400">{p.brand}</div></div>
                  </td>
                  <td className="text-right pr-6"><button onClick={()=>openEdit(p)} className="text-xs bg-black text-white px-3 py-1.5 rounded-full mr-2">Edit</button><button onClick={()=>del(p._id || p.id)} className="text-xs bg-red-50 text-red-600 px-3 py-1.5 rounded-full">Delete</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
      {showModal && (
        <div className="fixed inset-0 bg-black/60 backdrop-blur-sm z-50 flex items-center justify-center p-6">
          <form onSubmit={submit} className="bg-white w-full max-w-lg rounded-2xl p-8">
            <div className="flex justify-between"><h2 className="text-xl font-black">{editing?'Edit':'New'}</h2><button type="button" onClick={()=>setShowModal(false)}>✕</button></div>
            <div className="grid grid-cols-2 gap-3 mt-6">
              <input value={form.name} onChange={e=>setForm({...form,name:e.target.value})} placeholder="Product name" className="col-span-2 border p-3.5 rounded-xl text-sm" required />
              <input value={form.brand} onChange={e=>setForm({...form,brand:e.target.value})} placeholder="Brand" className="border p-3.5 rounded-xl text-sm" />
              <input value={form.sellingPrice} onChange={e=>setForm({...form,sellingPrice:e.target.value})} placeholder="Price" type="number" className="border p-3.5 rounded-xl text-sm" required />
              <input value={form.stock} onChange={e=>setForm({...form,stock:e.target.value})} placeholder="Stock" type="number" className="border p-3.5 rounded-xl text-sm" />
              <input value={form.image} onChange={e=>setForm({...form,image:e.target.value})} placeholder="Image URL" className="col-span-2 border p-3.5 rounded-xl text-sm" />
              <button className="col-span-2 bg-black text-white py-4 rounded-xl font-bold mt-2">{editing?'Update':'Create'}</button>
            </div>
          </form>
        </div>
      )}
    </div>
  );
}