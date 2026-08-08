import { useEffect, useState } from "react";

import {
  getProducts,
  addProduct,
  deleteProduct
} from "../services/api";

import "./Admin.css";

function Admin() {

  const [products, setProducts] = useState([]);

  const [form, setForm] = useState({
    name: "",
    brand: "",
    category: "",
    price: "",
    sizes: "",
    stock: "",
    description: "",
    featured: false,
  });

  const [image, setImage] = useState(null);

  useEffect(() => {
    loadProducts();
  }, []);

  const loadProducts = async () => {
    try {
      const data = await getProducts();

      setProducts(data.products);

    } catch (err) {

      console.error(err);

    }
  };

  const handleChange = (e) => {

    const { name, value, type, checked } = e.target;

    setForm({
      ...form,
      [name]: type === "checkbox" ? checked : value,
    });

  };

  const handleSubmit = async (e) => {

    e.preventDefault();

    const formData = new FormData();

    Object.keys(form).forEach((key) => {

      formData.append(key, form[key]);

    });

    if (image) {

      formData.append("image", image);

    }

    await addProduct(formData);

    alert("Product Added!");

    setForm({
      name: "",
      brand: "",
      category: "",
      price: "",
      sizes: "",
      stock: "",
      description: "",
      featured: false,
    });

    setImage(null);

    loadProducts();

  };

  const removeProduct = async (id) => {

    if (!window.confirm("Delete this product?")) return;

    await deleteProduct(id);

    loadProducts();

  };

  return (
    <div className="admin-page">

      <div className="admin-header">
        <div>
          <h1>Product Manager</h1>
          <p>Manage products for Monique Investments</p>
        </div>

        <div className="admin-stats">
          <div className="stat-card">
            <h2>{products.length}</h2>
            <span>Total Products</span>
          </div>
        </div>
      </div>

      <div className="admin-container">

        <div className="product-form-card">

          <h2>Add New Product</h2>

          <form onSubmit={handleSubmit}>

            <div className="image-upload">

             <input
                type="file"
                accept="image/*"
                onChange={(e) => setImage(e.target.files[0])}
              />

              {image && (
                <p className="selected-image">
                  Selected: {image.name}
                </p>
              )}

            </div>

            <div className="form-grid">

              <div>
               <label>Product Name</label>

               <input
                 name="name"
                 placeholder="Nike Air Max"
                 value={form.name}
                 onChange={handleChange}
                />
              </div>

              <div>
               <label>Brand</label>

               <input
                 name="brand"
                 placeholder="Nike"
                 value={form.brand}
                 onChange={handleChange}
                />
              </div>

              <div>
               <label>Category</label>

               <input
                 name="category"
                 placeholder="Sneakers"
                 value={form.category}
                 onChange={handleChange}
                />
              </div>

              <div>
               <label>Price (KSh)</label>

                <input
                 name="price"
                 type="number"
                 placeholder="4500"
                 value={form.price}
                 onChange={handleChange}
                />
              </div>

              <div>
               <label>Sizes</label>

               <input
                 name="sizes"
                 placeholder="40,41,42"
                 value={form.sizes}
                 onChange={handleChange}
                />
              </div>

              <div>
               <label>Stock</label>

                <input
                 name="stock"
                 type="number"
                 placeholder="25"
                 value={form.stock}
                 onChange={handleChange}
                />
              </div>

            </div>

            <label>Description</label>

            <textarea
             name="description"
             placeholder="Product description..."
             value={form.description}
             onChange={handleChange}
            />

            <label className="checkbox">

             <input
               type="checkbox"
               name="featured"
               checked={form.featured}
               onChange={handleChange}
              />

              Featured Product

            </label>

            <button className="save-btn" type="submit">
              Save Product
            </button>

          </form>

        </div>

        <div className="table-card">

          <h2>Products</h2>

          <table>

            <thead>

              <tr>
               <th>Image</th>
               <th>Name</th>
               <th>Price</th>
               <th>Stock</th>
               <th>Delete</th>
              </tr>

            </thead>

            <tbody>

              {products.map((product) => (

                <tr key={product.id}>

                  <td>

                    <img
                     className="product-image"
                     src={`http://localhost:3001${product.image_url}`}
                     alt={product.name}
                    />

                  </td>

                  <td>{product.name}</td>

                  <td>KSh {product.price}</td>

                  <td>{product.stock}</td>

                  <td>

                   <button
                     className="delete-btn"
                     onClick={() => removeProduct(product.id)}
                    >
                      Delete
                    </button>

                  </td>

                </tr>

              ))}

            </tbody>

          </table>

        </div>

      </div>

    </div>
  );

}

export default Admin;