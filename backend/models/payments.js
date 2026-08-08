import mongoose from "mongoose";

const paymentSchema = new mongoose.Schema({
    orderId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "Order"
    },
    phone: String,
    amount: Number,
    receipt: String,
    checkoutRequestId: String,
    status: {
        type: String,
        default: "pending"
    }
}, { timestamps: true });

const Payment = mongoose.model("Payment", paymentSchema);

export default Payment;