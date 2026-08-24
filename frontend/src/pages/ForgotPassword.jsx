import { useState } from 'react'

export default function ForgotPassword() {
  const [email, setEmail] = useState('samuelmach.312@gmail.com')
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState(null)

  const handleSubmit = async (e) => {
    e.preventDefault()
    setLoading(true)
    try {
      const API = import.meta.env.VITE_API_URL || 'https://monique-investments-website.onrender.com/api'
      const res = await fetch(`${API}/auth/forgot-password`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email })
      })
      const data = await res.json()
      console.log("FULL RESPONSE:", data)
      
      setResult(data)
      if (data.resetLink) {
        alert(`RESET LINK:\n${data.resetLink}\n\nCopy this link!`)
      } else {
        alert(data.message)
      }
    } catch (err) {
      alert(err.message)
    }
    setLoading(false)
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 p-4">
      <form onSubmit={handleSubmit} className="bg-white p-8 rounded-lg shadow max-w-md w-full">
        <h2 className="text-2xl font-bold mb-4">Forgot Password?</h2>
        <p className="text-sm text-gray-600 mb-4">If email exists, reset link sent</p>
        <input 
          type="email" 
          value={email}
          onChange={e=>setEmail(e.target.value)}
          className="w-full border p-3 rounded mb-4"
          placeholder="Email"
          required
        />
        <button disabled={loading} className="w-full bg-black text-white p-3 rounded">
          {loading ? 'Sending...' : 'Send Reset Link'}
        </button>
        
        {result?.resetLink && (
          <div className="mt-4 p-3 bg-green-50 border border-green-200 rounded break-all">
            <p className="text-sm font-bold">RESET LINK (copy):</p>
            <a href={result.resetLink} className="text-blue-600 underline text-sm">{result.resetLink}</a>
          </div>
        )}
        
        <a href="/login" className="block mt-4 text-center text-sm underline">← Back to Login</a>
      </form>
    </div>
  )
}