import { useCart } from '../context/CartContext';
import { useNavigate } from 'react-router-dom';

export default function Orders() {
  const { cart, updateQty, removeFromCart } = useCart();
  const navigate = useNavigate();
  const total = cart.reduce((sum, item) => sum + item.price * item.qty, 0);

  return (
    <div className="p-5 max-w-3xl mx-auto">
      <h2 className="text-2xl font-bold mb-5">Your Cart</h2>
      {cart.length === 0? (
        <p>No items in cart</p>
      ) : (
        <>
          {cart.map(item => (
            <div key={item.id} className="flex justify-between items-center p-4 border border-gray-200 rounded-lg mb-3">
              <div>
                <strong>{item.name}</strong>
                <div>KSh {item.price.toLocaleString()}</div>
              </div>
              <div className="flex items-center gap-2.5">
                <button onClick={() => updateQty(item.id, item.qty - 1)} className="w-8 h-8 border rounded">-</button>
                <span>x{item.qty}</span>
                <button onClick={() => updateQty(item.id, item.qty + 1)} className="w-8 h-8 border rounded">+</button>
                <button onClick={() => removeFromCart(item.id)} className="ml-2.5 bg-red-500 text-white px-3 py-1 rounded">Cancel</button>
              </div>
              <div><strong>KSh {(item.price * item.qty).toLocaleString()}</strong></div>
            </div>
          ))}
          <div className="mt-5 pt-5 border-t-2 border-black">
            <h3 className="text-xl font-bold">Total: KSh {total.toLocaleString()}</h3>

            <button 
              onClick={() => navigate('/checkout')}
              className="mt-5 bg-[#e93a0e] text-white px-4 py-2.5 rounded-lg font-bold hover:bg-[#c72c06] text-sm"
            >
              Proceed to Checkout
            </button>
          </div>
        </>
      )}
    </div>
  )
}