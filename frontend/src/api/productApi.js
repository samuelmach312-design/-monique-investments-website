import axios from 'axios';

const API = axios.create({
  baseURL: import.meta.env.VITE_API_URL || 'http://localhost:5000/api'
});

export const getProducts = (search) => API.get(`/products?search=${search || ''}`);
export const createProduct = (data) => API.post('/products', data);
export const updateProduct = (id, data) => API.put(`/products/${id}`, data);
export const deleteProducts = (ids) => API.delete('/products', { data: { ids } });
export const deleteOne = (id) => API.delete(`/products/${id}`);