const express = require("express");
const axios = require("axios");
const moment = require("moment");
require("dotenv").config();

const router = express.Router();

router.post("/stkpush", async (req, res) => {
    try {
    
        console.log('STK Push hit:', req.body)
        const { phone, amount } = req.body;

        // ENV VARIABLES
        const shortcode = process.env.MPESA_SHORTCODE; //6880156
        const passkey = process.env.MPESA_PASSKEY;
        const callbackUrl = process.env.MPESA_CALLBACK_URL;
        const timestamp = new Date().toISOString().replace(/[^0-9]/g, '').slice(0, -3);

        const password = Buffer.from(shortcode + passkey + timestamp).toString("base64");

        console.log({ shortcode, passkey: passkey?.slice(0,5) + '...', timestamp });
        // GET ACCESS TOKEN
        const tokenResponse = await axios.get(
            "https://sandbox.safaricom.co.ke/oauth/v1/generate?grant_type=client_credentials",
            {
                auth: {
                    username: process.env.MPESA_CONSUMER_KEY,
                    password: process.env.MPESA_CONSUMER_SECRET
                }
            }
        );

        const accessToken = tokenResponse.data.access_token;

        // CLEAN PHONE NUMBER
        let cleanedPhone = phone.replace(/\D/g, "");

        if (cleanedPhone.startsWith("0")) {
            cleanedPhone = "254" + cleanedPhone.substring(1);
        }

        // STK PUSH REQUEST
        const stkRes = await axios.post(
            "https://sandbox.safaricom.co.ke/mpesa/stkpush/v1/processrequest",
            {
                BusinessShortCode: shortcode, //6880156
                Password: password,           //base64 of shortcode + passkey + timestamp
                Timestamp: timestamp,         //"20260519094522" format
                TransactionType: "CustomerBuyGoodsOnline",
                Amount: Math.round(amount),
                PartyA: cleanedPhone,         //"254712345678"
                PartyB: shortcode,            //  6880156
                PhoneNumber: cleanedPhone,    //  "254712345678"
                CallBackURL: callbackUrl,     // ngrok URL from .env
                AccountReference: "Monique Shoes",
                TransactionDesc: "Payment for shoes"
            },
            {
                headers: {
                    Authorization: `Bearer ${accessToken}`
                }
            }
        );

        console.log("STK RESPONSE:", stkRes.data);

        res.json({
            success: true,
            message: "STK Push sent",
            data: stkRes.data
        });

    } catch (error) {
        console.log("========== MPESA FULL ERROR ==========");

        if (error.response) {
            console.log("STATUS:", error.response.status);

            console.log(
                "DATA:",
                JSON.stringify(error.response.data, null, 2)
            );

        } else {

            console.log("ERROR:", error.message);
        }

        console.log("======================================");


        res.status(500).json({
            success: false,
            error: error.response?.data || error.message
        });
    }
});

module.exports = router;