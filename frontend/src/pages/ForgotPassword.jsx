import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'

export default function ForgotPassword() {
  const [email, setEmail] = useState('')
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  const { forgotPassword } = useAuth()

  const handleSubmit = async (e) => {
    e.preventDefault()
    setError('')
    setMessage('')
    setLoading(true)
    const result = await forgotPassword(email)
    if (result.success) {
      setMessage(result.message)
      if (result.resetLink) {
        alert(`RESET LINK: ${result.resetLink}`)
        console.log('Reset link:', result.resetLink)
      }
    } else {
      setError(result.error)
    }
    setLoading(false)
  }

  return (
    <div className="min-h-screen bg-gray-50 flex items-center justify-center px-4">
      <div className="bg-white p-8 rounded-2xl shadow-xl border w-full max-w-md">
        <h2 className="text-2xl font-black text-center">Forgot Password?</h2>
        <p className="text-sm text-gray-500 text-center mt-1 mb-6">We'll send reset instructions</p>

        {error && <div className="bg-red-50 text-red-700 p-3 rounded-xl mb-4 text-sm">{error}</div>}
        {message && <div className="bg-green-50 text-green-700 p-3 rounded-xl mb-4 text-sm">{message}</div>}

        <form onSubmit={handleSubmit} className="space-y-4">
          <input
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            className="w-full px-4 py-3 bg-gray-50 border rounded-xl"
            placeholder="you@example.com"
          />
          <button type="submit" disabled={loading} className="w-full py-3 bg-black text-white rounded-xl font-bold">
            {loading ? 'Sending...' : 'Send Reset Link'}
          </button>
        </form>

        <div className="mt-6 text-center">
          <Link to="/login" className="text-sm font-bold text-blue-600">← Back to Login</Link>
        </div>
      </div>
    </div>
  )
}