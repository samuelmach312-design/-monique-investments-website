const express = require('express')
const router = express.Router()
const nodemailer = require('nodemailer')
const jwt = require('jsonwebtoken')
const User = require('../models/User') // <-- CHECK THIS PATH! Is it ../models/User or ./models/User ?
const bcrypt = require('bcryptjs')

// Transporter using YOUR env names
const transporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS
  }
})

// Verify transporter
transporter.verify((error, success) => {
  if (error) {
    console.log("SMTP ERROR:", error)
  } else {
    console.log("SMTP Ready to send emails")
  }
})

// FORGOT PASSWORD - THIS WAS 404 BEFORE
router.post('/forgot-password', async (req, res) => {
  try {
    const { email } = req.body
    console.log("Forgot request for:", email)
    
    const user = await User.findOne({ email })
    if (!user) {
      console.log("User not found:", email)
      return res.json({ message: "If this email exists, a reset link was sent to your inbox" })
    }

    const resetToken = jwt.sign(
      { id: user._id, email: user.email },
      process.env.JWT_SECRET,
      { expiresIn: '1h' }
    )

    const frontendUrl = process.env.FRONTEND_URL || 'http://localhost:5173'
    const resetLink = `${frontendUrl}/reset-password?token=${resetToken}`

    console.log("RESET LINK:", resetLink)

    await transporter.sendMail({
      from: `"Monique Investments" <${process.env.SMTP_USER}>`,
      to: email,
      subject: "Reset Your Password - Monique Investments",
      html: `
        <div style="font-family: Arial; max-width:600px; margin:auto; border:1px solid #eee; border-radius:16px; padding:24px;">
          <h2 style="color:#0f172a;">Reset Password</h2>
          <p>Hi ${user.name || ''}, you requested a password reset.</p>
          <a href="${resetLink}" style="display:inline-block; background:#0f172a; color:white; padding:12px 24px; border-radius:9999px; text-decoration:none; font-weight:bold;">Reset Password</a>
          <p style="color:#666; font-size:12px; margin-top:16px;">Link expires in 1 hour. If you didn't request, ignore.</p>
          <p style="color:#999; font-size:11px; word-break:break-all;">${resetLink}</p>
        </div>
      `
    })

    console.log("Email sent to:", email)

    res.json({ 
      message: "If this email exists, a reset link was sent to your inbox",
      resetLink: resetLink // FOR TESTING - remove in production!
    })

  } catch (err) {
    console.error("Forgot error:", err)
    res.status(500).json({ message: "Failed to send email: " + err.message })
  }
})

// RESET PASSWORD
router.post('/reset-password', async (req, res) => {
  try {
    const { token, password } = req.body
    console.log("Reset attempt with token")
    
    const decoded = jwt.verify(token, process.env.JWT_SECRET)
    const user = await User.findById(decoded.id)
    if (!user) return res.status(400).json({ message: "Invalid token" })
    
    // Hash password
    const hashedPassword = await bcrypt.hash(password, 10)
    user.password = hashedPassword
    await user.save()
    
    res.json({ message: "Password reset successful!" })
  } catch (err) {
    console.error("Reset error:", err)
    res.status(400).json({ message: "Invalid or expired token" })
  }
})

module.exports = router