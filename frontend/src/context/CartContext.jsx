import { createContext, useContext, useState, useEffect } from 'react';

const CartContext = createContext();

export function useCart() {
  const context = useContext(CartContext);
  if (!context) {
    throw new Error('useCart must be used within CartProvider');
  }
  return context;
}

export function CartProvider({ children }) {
  const [cart, setCart] = useState([]);

  // Load cart from localStorage on mount
  useEffect(() => {
    try {
      const saved = localStorage.getItem('cart');
      if (saved) {
        const parsed = JSON.parse(saved);
        setCart(Array.isArray(parsed)? parsed : []);
      }
    } catch (err) {
      console.error('Failed to load cart:', err);
      setCart([]);
    }
  }, []);

  // Save cart to localStorage whenever it changes
  useEffect(() => {
    localStorage.setItem('cart', JSON.stringify(cart || []));
  }, [cart]);

  const addToCart = (product) => {
    setCart(prev => {
      const current = Array.isArray(prev)? prev : [];
      const key = `${product.id}-${product.selectedSize || 'default'}`;
      const existing = current.find(item => item.key === key);

      if (existing) {
        return current.map(item =>
          item.key === key? {...item, qty: (item.qty || 1) + 1 } : item
        );
      }
      return [...current, {
     ...product,
        key,
        qty: 1,
        price: Number(product.price) || 0,
        img: product.image_url || product.img,
        image: product.image_url || product.img
      }];
    });
  };

  const removeFromCart = (key) => {
    setCart(prev => (Array.isArray(prev)? prev : []).filter(item => item.key!== key));
  };

  const updateQty = (key, qty) => {
    if (qty <= 0) {
      removeFromCart(key);
      return;
    }
    setCart(prev =>
      (Array.isArray(prev)? prev : []).map(item =>
        item.key === key? {...item, qty: Number(qty) } : item
      )
    );
  };

  const clearCart = () => {
    setCart([]);
  };

  const checkout = async (orderDetails) => {
    try {
      await new Promise(r => setTimeout(r, 1000));

      const order = {
        id: 'ORD-' + Date.now(),
        items: cart || [],
        total: total,
        date: new Date().toISOString(),
        status: 'confirmed',
     ...orderDetails
      };

      const orders = JSON.parse(localStorage.getItem('orders') || '[]');
      orders.push(order);
      localStorage.setItem('orders', JSON.stringify(orders));

      clearCart();

      return {
        success: true,
        orderId: order.id,
        message: 'Order placed successfully!'
      };
    } catch (err) {
      return {
        success: false,
        error: 'Order failed. Please try again.'
      };
    }
  };

  const total = (Array.isArray(cart)? cart : []).reduce((sum, item) => {
    const price = Number(item.price) || 0;
    const qty = Number(item.qty) || 0;
    return sum + (price * qty);
  }, 0);

  const itemCount = (Array.isArray(cart)? cart : []).reduce((sum, item) => {
    return sum + (Number(item.qty) || 0);
  }, 0);

  return (
    <CartContext.Provider value={{
      cart: cart || [],
      addToCart,
      removeFromCart,
      updateQty,
      clearCart,
      checkout,
      total,
      itemCount
    }}>
      {children}
    </CartContext.Provider>
  );
}