import mongoose from "mongoose";

const orderSchema = new mongoose.Schema({
    items: Array,
    totalAmount: Number,
    phone: String,
    paymentId: {
        type: mongoose.Schema.Types.ObjectId,
        ref: "Payment"
    },
    status: {
        type: String,
        default: "pending"
    }
}, { timestamps: true });

const Order = mongoose.model("Order", orderSchema);

export default Order;