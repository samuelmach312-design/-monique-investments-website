const express = require('express')
const router = express.Router()
const nodemailer = require('nodemailer')
const jwt = require('jsonwebtoken')
const User = require('../models/user')
const bcrypt = require('bcryptjs')

const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 587,
  secure: false,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS
  },
  tls: { rejectUnauthorized: false },
  connectionTimeout: 10000,
  greetingTimeout: 10000,
  socketTimeout: 10000
})

// BYPASS VERIFY - CAUSES ETIMEOUT IN KENYA
console.log("SMTP BYPASSED - Check console for reset links")

router.post('/forgot-password', async (req, res) => {
  try {
    const { email } = req.body
    console.log("Forgot request for:", email)
    
    const user = await User.findOne({ email })
    if (!user) {
      return res.json({ message: "If this email exists, a reset link was sent to your inbox" })
    }

    const resetToken = jwt.sign(
      { id: user._id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: '1h' }
    )

    const frontendUrl = process.env.FRONTEND_URL || 'https://monique-investments.vercel.app'
    const resetLink = `${frontendUrl}/reset-password?token=${resetToken}`

    console.log("RESET LINK:", resetLink)
    console.log("=== EMAIL SKIPPED DUE TO DNS, BUT LINK WORKS ===")
    console.log("SEND THIS LINK TO USER:", resetLink)

    res.json({ 
      message: "Reset link generated - check backend logs!",
      resetLink: resetLink
    })

  } catch (err) {
    console.error("Forgot error:", err)
    res.status(500).json({ message: err.message })
  }
})

router.post('/reset-password', async (req, res) => {
  try {
    const { token, password } = req.body
    const decoded = jwt.verify(token, process.env.JWT_SECRET)
    const user = await User.findById(decoded.id)
    if (!user) return res.status(400).json({ message: "Invalid token" })
    
    user.password = await bcrypt.hash(password, 10)
    await user.save()
    
    res.json({ message: "Password reset successful!" })
  } catch (err) {
    res.status(400).json({ message: "Invalid or expired token" })
  }
})

module.exports = router