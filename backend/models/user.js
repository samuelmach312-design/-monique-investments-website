const mongoose = require('mongoose') // ✅ CommonJS
const bcrypt = require('bcryptjs')

const userSchema = new mongoose.Schema({
  name: { type: String, required: true },
  email: { type: String, required: true, unique: true },
  password: { type: String, required: true }
}, { timestamps: true })

// Hash before save
userSchema.pre('save', async function(next) {
  if (!this.isModified('password')) return next()
  const hashed = await bcrypt.hash(this.password, 10)
  this.password = hashed
  next()
})

module.exports = mongoose.model('User', userSchema)