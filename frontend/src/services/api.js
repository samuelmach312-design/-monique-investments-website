const API_URL = "http://localhost:3001/api/products";

// ==============================
// GET ALL PRODUCTS
// ==============================
export const getProducts = async () => {
  const response = await fetch(API_URL);

  if (!response.ok) {
    throw new Error("Failed to fetch products");
  }

  return await response.json();
};

// ==============================
// GET ONE PRODUCT
// ==============================
export const getProduct = async (id) => {
  const response = await fetch(`${API_URL}/${id}`);

  if (!response.ok) {
    throw new Error("Failed to fetch product");
  }

  return await response.json();
};

// ==============================
// ADD PRODUCT
// ==============================
export const addProduct = async (formData) => {
  const response = await fetch(API_URL, {
    method: "POST",
    body: formData,
  });

  return await response.json();
};

// ==============================
// UPDATE PRODUCT
// ==============================
export const updateProduct = async (id, formData) => {
  const response = await fetch(`${API_URL}/${id}`, {
    method: "PUT",
    body: formData,
  });

  return await response.json();
};

// ==============================
// DELETE PRODUCT
// ==============================
export const deleteProduct = async (id) => {
  const response = await fetch(`${API_URL}/${id}`, {
    method: "DELETE",
  });

  return await response.json();
};