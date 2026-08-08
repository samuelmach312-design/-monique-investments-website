// routes/mpesa.js
const express = require('express');
const axios = require('axios');
const router = express.Router();

// Get access token
async function getAccessToken() {
  const consumerKey = process.env.MPESA_CONSUMER_KEY;
  const consumerSecret = process.env.MPESA_CONSUMER_SECRET;
  
  if (!consumerKey || !consumerSecret) {
    throw new Error('Missing MPESA_CONSUMER_KEY or MPESA_CONSUMER_SECRET in .env');
  }
  
  const auth = Buffer.from(`${consumerKey}:${consumerSecret}`).toString('base64');
  
  const res = await axios.get(
    'https://sandbox.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials',
    {
      headers: { Authorization: `Basic ${auth}` }
    }
  );
  return res.data.access_token;
}

// STK Push endpoint - POST /api/mpesa/stkpush
router.post('/stkpush', async (req, res) => {
  try {
    const { phone, amount, orderDetails } = req.body;

    if (!phone || !amount) {
      return res.status(400).json({ 
        success: false, 
        error: 'Phone and amount are required' 
      });
    }

    const token = await getAccessToken();
    
    const timestamp = new Date().toISOString().replace(/[^0-9]/g, '').slice(0, 14);
    const password = Buffer.from(
      process.env.MPESA_SHORTCODE + process.env.MPESA_PASSKEY + timestamp
    ).toString('base64');

    const data = {
      BusinessShortCode: process.env.MPESA_SHORTCODE,
      Password: password,
      Timestamp: timestamp,
      TransactionType: 'CustomerPayBillOnline',
      Amount: Math.round(amount), // M-Pesa needs integer
      PartyA: phone, // 2547XXXXXXXX
      PartyB: process.env.MPESA_SHORTCODE,
      PhoneNumber: phone,
      CallBackURL: process.env.MPESA_CALLBACK_URL,
      AccountReference: 'MoniqueShoes',
      TransactionDesc: 'Payment for shoes'
    };

    const response = await axios.post(
      'https://sandbox.safaricom.co.ke/mpesa/stkpush/v1/processrequest',
      data,
      { headers: { Authorization: `Bearer ${token}` } }
    );

    // Save order to DB with CheckoutRequestID for later verification
    // Example: db.orders.create({ ...orderDetails, checkoutRequestId: response.data.CheckoutRequestID })

    console.log('STK Push Response:', response.data);
    res.json({ success: true, data: response.data });
    
  } catch (error) {
    console.error('STK Push Error:', error.response?.data || error.message);
    res.status(500).json({ 
      success: false, 
      error: error.response?.data || error.message 
    });
  }
});

// Callback - M-Pesa calls this after payment - POST /api/mpesa/callback
router.post('/callback', (req, res) => {
  const callbackData = req.body;
  console.log('M-Pesa Callback:', JSON.stringify(callbackData, null, 2));
  
  // Example: Update order status in DB based on ResultCode
  // const { ResultCode, CheckoutRequestID } = callbackData.Body.stkCallback;
  // if (ResultCode === 0) {
  //   // Payment successful - update order to 'paid'
  // } else {
  //   // Payment failed - update order to 'failed'
  // }
  
  res.json({ ResultCode: 0, ResultDesc: 'Success' });
});

// This line is critical - exports the router function
module.exports = router;