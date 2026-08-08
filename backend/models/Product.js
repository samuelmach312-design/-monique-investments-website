const mongoose = require("mongoose");

const ProductSchema = new mongoose.Schema({
    code: {
        type: String,
        unique: true,
        default: () => `MONQ-${Date.now().toString().slice(-6)}-${Math.floor(100 + Math.random() * 900)}`
    },
    name: {
        type: String,
        required: true,
        trim: true,
        index: true
    },
    category: {
        type: String,
        required: true,
        index: true,
        enum: ['Sneakers', 'Heels', 'Boots', 'Sandals', 'Loafers', 'Sports', 'Kids', 'Accessories', 'Household'],
        default: 'Sneakers'
    },
    brand: {
        type: String,
        required: true,
        index: true,
        enum: ['Nike', 'Adidas', 'Puma', 'New Balance', 'Jordan', 'Converse', 'Vans', 'Gucci', 'Louis Vuitton', 'Monique Original', '36', 'Other'],
        default: 'Nike'
    },
    // Shoe specific
    size: {
        type: String,
        default: '42'
    },
    color: {
        type: String,
        default: 'Black'
    },
    // Pricing - keep all 3 for compatibility
    price: {
        type: Number,
        required: true,
        min: 1
    },
    purchasePrice: {
        type: Number,
        default: 0,
        min: 0
    },
    sellingPrice: {
        type: Number,
        required: true,
        min: 1
    },
    discount: {
        type: String,
        default: 'No discount'
    },
    stock: {
        type: Number,
        required: true,
        min: 0,
        default: 0
    },
    image: {
        type: String,
        required: true,
        validate: {
            validator: v => /^https?:\/\/.+/.test(v) || v === '',
            message: "Invalid image URL"
        }
    },
    description: {
        type: String,
        default: ""
    },
    createdBy: {
        type: String,
        enum: ['Samuel', 'Monicah', 'Frank', 'Admin'],
        required: true,
        default: 'Samuel'
    },
    isActive: {
        type: Boolean,
        default: true
    }
}, { timestamps: true });

// Search indexes
ProductSchema.index({ name: "text", description: "text", brand: "text" });

// Auto-sync price <-> sellingPrice so both never break
ProductSchema.pre('save', function(next) {
    if (this.isModified('price') && !this.isModified('sellingPrice')) {
        this.sellingPrice = this.price;
    }
    if (this.isModified('sellingPrice') && !this.isModified('price')) {
        this.price = this.sellingPrice;
    }
    if (!this.price) this.price = this.sellingPrice;
    if (!this.sellingPrice) this.sellingPrice = this.price;
    next();
});

module.exports = mongoose.model("Product", ProductSchema);