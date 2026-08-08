import { useProducts } from '../hooks/useProducts';

export default function Products() {
  const { products, loading, error } = useProducts();

  if (loading) return <div className="p-4">Loading dukas...</div>;
  if (error) return <div className="p-4 text-red-500">Error: {error}. Showing saved products.</div>;

  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-6 p-4">
      {products.filter(p => p.inStock).map(product => (
        <div key={product.id} className="border rounded-lg shadow p-4">
          <img 
            src={product.imageUrl} 
            alt={product.name}
            className="w-full h-48 object-cover rounded mb-3"
            loading="lazy"
          />
          <h3 className="font-bold text-lg">{product.name}</h3>
          <p className="text-gray-600 text-sm mb-2">{product.description}</p>
          <div className="flex justify-between items-center mt-3">
            <span className="text-xl font-semibold">Ksh {product.price}</span>
            <button className="bg-green-600 text-white px-4 py-2 rounded">
              Add to Cart
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}
