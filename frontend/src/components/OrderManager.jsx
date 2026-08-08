import React, { useState, useEffect } from 'react';

export default function OrderManager() {
  const [orders, setOrders] = useState([]);

  // Load from localStorage on first load
  useEffect(() => {
    const saved = JSON.parse(localStorage.getItem("orders")) || [];
    setOrders(saved);
  }, []);

  // Save to localStorage whenever orders change
  useEffect(() => {
    localStorage.setItem("orders", JSON.stringify(orders));
  }, [orders]);

  // Add new item to cart
  function addToCart(name, price) {
    setOrders(prev => {
      const existing = prev.find(o => o.name === name);
      if (existing) {
        // Item exists: increase qty
        return prev.map(o =>
          o.name === name? {...o, qty: o.qty + 1 } : o
        );
      }
      // New item: add to list
      return [...prev, { id: Date.now(), name, price, qty: 1 }];
    });
  }

  // Increase qty by 1
  function increaseQty(id) {
    setOrders(prev =>
      prev.map(o => o.id === id? {...o, qty: o.qty + 1 } : o)
    );
  }

  // Decrease qty by 1, remove if qty hits 0
  function decreaseQty(id) {
    setOrders(prev =>
      prev.map(o => o.id === id? {...o, qty: o.qty - 1 } : o)
       .filter(o => o.qty > 0) // auto-remove if qty = 0
    );
  }

  // Cancel/Remove item completely
  function removeItem(id) {
    setOrders(prev => prev.filter(o => o.id!== id));
  }

  // Clear all orders
  function clearAll() {
    setOrders([]);
  }

  // Calculate total
  const total = orders.reduce((sum, o) => sum + o.price * o.qty, 0);
  const totalItems = orders.reduce((sum, o) => sum + o.qty, 0);

  return (
    <div style={{ padding: 20, maxWidth: 600 }}>
      <h2>Complete Your Order</h2>
      <p>Items: {totalItems}</p>

      {/* Example: Add items - remove this if you add from product page */}
      <div style={{ marginBottom: 20, display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        <button onClick={() => addToCart('574 Core', 9500)}>Add 574 Core</button>
        <button onClick={() => addToCart('Air Force 1', 10900)}>Add Air Force 1</button>
        <button onClick={() => addToCart('Ultraboost 23', 14900)}>Add Ultraboost 23</button>
        <button onClick={() => addToCart('RS-X Reinvent', 9800)}>Add RS-X Reinvent</button>
      </div>

      {orders.length === 0? (
        <p>No orders yet</p>
      ) : (
        <>
          {orders.map(o => (
            <div key={o.id} style={{
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center',
              padding: 15,
              border: '1px solid #ddd',
              borderRadius: 8,
              marginBottom: 10
            }}>
              <div>
                <strong>{o.name}</strong>
                <div>KSh {o.price.toLocaleString()}</div>
              </div>

              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <button onClick={() => decreaseQty(o.id)} style={{width: 30}}>-</button>
                <span>x{o.qty}</span>
                <button onClick={() => increaseQty(o.id)} style={{width: 30}}>+</button>
                <button
                  onClick={() => removeItem(o.id)}
                  style={{marginLeft: 10, background: '#ff4444', color: 'white', border: 'none', padding: '5px 10px', borderRadius: 4}}
                >
                  Cancel
                </button>
              </div>

              <div>
                <strong>KSh {(o.price * o.qty).toLocaleString()}</strong>
              </div>
            </div>
          ))}

          <div style={{marginTop: 20, paddingTop: 20, borderTop: '2px solid #000'}}>
            <h3>Total: KSh {total.toLocaleString()}</h3>
            <button onClick={clearAll} style={{background: '#666', color: 'white', padding: '10px 20px', border: 'none', borderRadius: 4}}>
              Clear All Orders
            </button>
          </div>
        </>
      )}
    </div>
  );
}