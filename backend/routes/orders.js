const express = require('express');
const router = express.Router();
const axios = require('axios');

const orders = [];

// Your WhatsApp - no + sign, format: 254723808067
const ADMIN_WHATSAPP = '254723808067';
const CALLMEBOT_APIKEY = '6865331';

// M-Pesa Paybill Details
const PAYBILL_NUMBER = '507900';
const ACCOUNT_NUMBER = '2016253';

router.post('/', async (req, res) => {
  try {
    const { cart, total, phoneNumber, userId, customer } = req.body;

    if (!cart?.length) {
      return res.status(400).json({
        success: false,
        error: 'Cart is empty'
      });
    }

    if (!customer?.name || !customer?.phone || !customer?.email) {
      return res.status(400).json({
        success: false,
        error: 'Missing customer details'
      });
    }

    const order = {
      id: Date.now(),
      userId: userId || null,
      items: cart,
      total,
      customer,
      phoneNumber,
      status: 'pending_payment',
      createdAt: new Date().toISOString()
    };

    orders.push(order);
    console.log('NEW ORDER:', order);

    // Build WhatsApp message
    const itemsList = cart.map(i =>
      `• ${i.name} x${i.qty} - KSh ${(i.price * i.qty).toLocaleString()}`
    ).join('\n');

    const message =
      `*NEW ORDER #${order.id}*\n\n` +
      `*Customer:* ${customer.name}\n` +
      `*Phone:* ${phoneNumber}\n` +
      `*Email:* ${customer.email}\n` +
      `*Address:* ${customer.address}, ${customer.city}\n\n` +
      `*Items:*\n${itemsList}\n\n` +
      `*Total: KSh ${total.toLocaleString()}*\n\n` +
      `*Payment Method:* M-Pesa Paybill\n` +
      `*Paybill Number:* ${PAYBILL_NUMBER}\n` +
      `*Account Number:* ${ACCOUNT_NUMBER}\n\n` +
      `*Status:* Awaiting Payment\n` +
      `*Notes:* ${customer.notes || 'None'}`;

    // Send to WhatsApp using CallMeBot
    const whatsappUrl = `https://api.callmebot.com/whatsapp.php?phone=${ADMIN_WHATSAPP}&text=${encodeURIComponent(message)}&apikey=${CALLMEBOT_APIKEY}`;

    axios.get(whatsappUrl)
      .then(() => console.log('WhatsApp sent to', ADMIN_WHATSAPP))
      .catch(e => console.log('WhatsApp failed:', e.message));

    res.status(201).json({
      success: true,
      message: 'Order placed. Pay using the M-Pesa Paybill below.',
      orderId: order.id,
      paybill: PAYBILL_NUMBER,
      accountNumber: ACCOUNT_NUMBER,
      order
    });

  } catch (err) {
    console.error('Order error:', err);
    res.status(500).json({
      success: false,
      error: 'Server error'
    });
  }
});

router.get('/', (req, res) => {
  res.json({
    success: true,
    orders
  });
});

module.exports = router;