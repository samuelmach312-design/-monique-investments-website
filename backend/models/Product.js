const mongoose = require("mongoose");

const ProductSchema = new mongoose.Schema({
    code: {
        type: String,
        unique: true,
        default: () => `MONQ-${Date.now().toString().slice(-6)}-${Math.floor(100 + Math.random() * 900)}`
    },
    name: { type: String, required: true, trim: true, index: true },
    category: {
        type: String,
        required: true,
        index: true,
        enum: ['Sneakers', 'Heels', 'Boots', 'Sandals', 'Loafers', 'Sports', 'Kids', 'Accessories', 'Household', 'Shoes', 'Lifestyle', 'Slides', 'Shoe Care', 'Belt', 'Belts'],
        default: 'Shoes'
    },
    brand: {
        type: String,
        required: true,
        index: true,
        enum: ['Nike', 'Adidas', 'Puma', 'New Balance', 'Jordan', 'Converse', 'Vans', 'Gucci', 'Louis Vuitton', 'Monique Original', 'Monique', 'CAT', '36', 'Other'],
        default: 'Monique'
    },
    size: { type: String, default: '42' },
    color: { type: String, default: 'Black' },
    price: { type: Number, required: true, min: 1 },
    purchasePrice: { type: Number, default: 0 },
    sellingPrice: { type: Number, required: true, min: 1 },
    discount: { type: String, default: 'No discount' },
    stock: { type: Number, default: 50, min: 0 },
    image: { type: String, default: "" },
    image_url: { type: String, default: "" },
    description: { type: String, default: "" },
    createdBy: { type: String, enum: ['Samuel', 'Monicah', 'Frank', 'Admin'], default: 'Samuel' },
    isActive: { type: Boolean, default: true }
}, { timestamps: true });

ProductSchema.index({ name: "text", description: "text", brand: "text" });

ProductSchema.pre('save', function(next) {
    if (this.isModified('price') &&!this.isModified('sellingPrice')) this.sellingPrice = this.price;
    if (this.isModified('sellingPrice') &&!this.isModified('price')) this.price = this.sellingPrice;
    if (!this.price) this.price = this.sellingPrice;
    if (!this.sellingPrice) this.sellingPrice = this.price;
    next();
});

module.exports = mongoose.model("Product", ProductSchema);