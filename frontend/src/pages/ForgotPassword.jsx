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
        console.log('Reset link:', result.resetLink)
        // FOR TESTING ONLY - remove later
        // alert(`TEST LINK: ${result.resetLink}`)
      }
    } else {
      setError(result.error)
    }
    setLoading(false)
  }

  return (
    <div className="min-h-screen bg-[#f8fafc] flex items-center justify-center px-4">
      <div className="bg-white p-8 rounded- shadow-xl shadow-blue-900/5 border border-gray-100 w-full max-w-md">
        <div className="text-center mb-7">
          <div className="w-12 h-12 bg-[#0f172a] rounded-full flex items-center justify-center mx-auto mb-3">
            <span className="text-white text-xl">🔒</span>
          </div>
          <h2 className="text- font-black text-[#0f172a] tracking-tight">Forgot Password?</h2>
          <p className="text-sm text-gray-500 mt-1">No worries, we'll send you reset instructions</p>
        </div>

        {error && (
          <div className="bg-red-50 text-red-700 p-3.5 rounded-xl mb-4 text- font-medium border border-red-100 flex gap-2">
            <span>⚠️</span> {error}
          </div>
        )}

        {message && (
          <div className="bg-green-50 text-green-700 p-3.5 rounded-xl mb-4 text- font-medium border border-green-100 flex gap-2">
            <span>✅</span> {message}
          </div>
        )}

        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="block text- font-bold text-gray-500 uppercase tracking-widest mb-2">
              Email Address
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              disabled={loading}
              className="w-full px-4 py-3.5 bg-gray-50 border border-gray-200 rounded-xl focus:outline-none focus:bg-white focus:border-blue-500 focus:ring-4 focus:ring-blue-50 disabled:bg-gray-100 text-sm font-medium transition-all"
              placeholder="you@example.com"
            />
          </div>

          <button
            type="submit"
            disabled={loading}
            className="w-full py-3.5 bg-[#0f172a] text-white rounded-xl hover:bg-black transition-all disabled:opacity-50 font-bold text-sm shadow-lg shadow-gray-900/10 flex items-center justify-center gap-2"
          >
            {loading? (
              <>
                <span className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin"></span>
                Sending...
              </>
            ) : (
              'Send Reset Link'
            )}
          </button>
        </form>

        <div className="mt-7 text-center">
          <Link to="/login" className="text-sm font-bold text-[#3b82f6] hover:text-blue-700 inline-flex items-center gap-1.5">
            ← Back to Login
          </Link>
        </div>

        {message && (
          <p className="text- text-center text-gray-400 mt-6 leading-relaxed">
            Didn't receive email? Check spam folder.<br/>Link expires in 1 hour.
          </p>
        )}
      </div>
    </div>
  )
}