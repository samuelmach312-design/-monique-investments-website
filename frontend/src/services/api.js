const BASE = (import.meta.env.VITE_API_URL || 'http://localhost:3001/api').replace(/\/$/, '');
const API_URL = BASE.endsWith('/mongo-products') ? BASE : BASE + '/mongo-products';

export const getProducts = async () => {
  const r = await fetch(API_URL);
  if (!r.ok) throw new Error('Failed to fetch products');
  const data = await r.json();
  return Array.isArray(data) ? { products: data } : data;
};
export const getProduct = async (id) => {
  const r = await fetch(\/\);
  if (!r.ok) throw new Error('Failed to fetch product');
  return await r.json();
};
export const addProduct = async (formData) => {
  let body, headers={};
  if (formData instanceof FormData) {
    const obj={};
    formData.forEach((v,k)=>obj[k]=v);
    if(obj.price){ obj.sellingPrice=Number(obj.price); obj.price=Number(obj.price); }
    if(obj.stock) obj.stock=Number(obj.stock);
    if(!obj.image) obj.image='https://images.unsplash.com/photo-1542291026-7eec264c27ff';
    body=JSON.stringify(obj);
    headers={"Content-Type":"application/json"};
  } else { body=JSON.stringify(formData); headers={"Content-Type":"application/json"}; }
  const r = await fetch(API_URL, {method:"POST", headers, body});
  return await r.json();
};
export const updateProduct = async (id, fd) => {
  const body = fd instanceof FormData ? JSON.stringify(Object.fromEntries(fd)) : JSON.stringify(fd);
  const r = await fetch(\/\, {method:"PUT", headers:{"Content-Type":"application/json"}, body});
  return await r.json();
};
export const deleteProduct = async (id) => {
  const r = await fetch(\/\, {method:"DELETE"});
  return await r.json();
};
