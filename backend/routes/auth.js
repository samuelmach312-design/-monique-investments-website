const express = require('express')
const router = express.Router()
const { neon } = require('@neondatabase/serverless')
const jwt = require('jsonwebtoken')
const bcrypt = require('bcryptjs')

const sql = process.env.DATABASE_URL? neon(process.env.DATABASE_URL) : null

console.log("SMTP BYPASSED - Using Neon + Console Reset Links")

router.post('/forgot-password', async (req, res) => {
  try {
    const { email } = req.body
    console.log("Forgot request for:", email)

    if (!sql) return res.status(500).json({ message: "No DB" })

    const users = await sql`SELECT * FROM users WHERE email = ${email.toLowerCase()}`
    if (users.length === 0) {
      return res.json({ message: "If this email exists, a reset link was sent" })
    }

    const resetToken = jwt.sign(
      { id: users[0].id, email: users[0].email },
      process.env.JWT_SECRET || 'monique-secret-key-2024',
      { expiresIn: '1h' }
    )

    const frontendUrl = process.env.FRONTEND_URL || 'https://monique-investments.vercel.app'
    const resetLink = `${frontendUrl}/reset-password?token=${resetToken}`

    console.log("==============================")
    console.log("RESET LINK FOR", email)
    console.log(resetLink)
    console.log("==============================")

    res.json({
      message: "Reset link generated! Check alert",
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
    const decoded = jwt.verify(token, process.env.JWT_SECRET || 'monique-secret-key-2024')

    const hashed = await bcrypt.hash(password, 10)
    await sql`UPDATE users SET password = ${hashed} WHERE id = ${decoded.id}`

    res.json({ message: "Password reset successful! You can now login." })
  } catch (err) {
    console.error(err)
    res.status(400).json({ message: "Invalid or expired token" })
  }
})

router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body
    const users = await sql`SELECT * FROM users WHERE email = ${email.toLowerCase()}`
    if (users.length === 0) return res.status(400).json({ message: "Invalid credentials" })

    const isMatch = await bcrypt.compare(password, users[0].password)
    if (!isMatch) return res.status(400).json({ message: "Invalid credentials" })

    const token = jwt.sign({ id: users[0].id }, process.env.JWT_SECRET || 'monique-secret-key-2024', { expiresIn: '7d' })
    res.json({ token, user: { id: users[0].id, email: users[0].email, name: users[0].name } })
  } catch (e) {
    console.error(e)
    res.status(500).json({ message: "Server error" })
  }
})

router.post('/register', async (req, res) => {
  try {
    const { email, password, name } = req.body
    const hashed = await bcrypt.hash(password, 10)
    const result = await sql`INSERT INTO users (email, password, name) VALUES (${email.toLowerCase()}, ${hashed}, ${name}) RETURNING id, email, name`
    const token = jwt.sign({ id: result[0].id }, process.env.JWT_SECRET || 'monique-secret-key-2024', { expiresIn: '7d' })
    res.json({ token, user: result[0] })
  } catch (e) {
    console.error(e)
    res.status(400).json({ message: "User already exists" })
  }
})

module.exports = router