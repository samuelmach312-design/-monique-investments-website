const BASE = (import.meta.env.VITE_API_URL || 'http://localhost:3001/api').replace(/\/$/, '');
const API_URL = BASE.endsWith('/mongo-products') ? BASE : BASE + '/mongo-products';

export const getProducts = async () => {
  const r = await fetch(API_URL);
  if (!r.ok) throw new Error('Failed to fetch products');
  const data = await r.json();
  return Array.isArray(data) ? { products: data } : data;
};

export const getProduct = async (id) => {
  const r = await fetch(`${API_URL}/${id}`);
  if (!r.ok) throw new Error('Failed to fetch product');
  return await r.json();
};

export const addProduct = async (formData) => {
  // FIXED: Actually send FormData with file + admin header
  const isFormData = formData instanceof FormData;
  const headers = { "x-admin-name": "Samuel" };
  let body;

  if (isFormData) {
    // Keep file! Don't JSON.stringify
    body = formData;
    // Ensure numbers
    if (body.has('price')) {
      const p = body.get('price');
      body.set('price', String(p));
    }
  } else {
    headers["Content-Type"] = "application/json";
    const obj = { ...formData };
    if (obj.price) obj.price = Number(obj.price);
    if (obj.sellingPrice) obj.sellingPrice = Number(obj.sellingPrice);
    if (obj.stock) obj.stock = Number(obj.stock);
    body = JSON.stringify(obj);
  }

  const r = await fetch(API_URL, { method: "POST", headers, body });
  if (!r.ok) {
    const text = await r.text();
    throw new Error(text || 'Failed to add product');
  }
  return await r.json();
};

export const updateProduct = async (id, fd) => {
  const isForm = fd instanceof FormData;
  const headers = { "x-admin-name": "Samuel" };
  if (!isForm) headers["Content-Type"] = "application/json";
  const body = isForm ? fd : JSON.stringify(fd);
  const r = await fetch(`${API_URL}/${id}`, { method: "PUT", headers, body });
  if (!r.ok) throw new Error('Failed to update');
  return await r.json();
};

export const deleteProduct = async (id) => {
  const r = await fetch(`${API_URL}/${id}`, { 
    method: "DELETE",
    headers: { "x-admin-name": "Samuel" }
  });
  if (!r.ok) throw new Error('Failed to delete');
  return await r.json();
};
