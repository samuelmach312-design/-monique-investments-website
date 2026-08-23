import { createContext, useContext, useState, useEffect } from 'react'

const AuthContext = createContext()

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider')
  }
  return context
}

// CHANGE THIS TO YOUR REAL BACKEND URL
const API_URL = import.meta.env.VITE_API_URL || 'http://localhost:3001'

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const savedUser = localStorage.getItem('user')
    const token = localStorage.getItem('token')
    if (savedUser && token) {
      try {
        setUser(JSON.parse(savedUser))
      } catch (err) {
        localStorage.removeItem('user')
        localStorage.removeItem('token')
      }
    }
    setLoading(false)
  }, [])

  const login = async (email, password) => {
    try {
      const res = await fetch(`${API_URL}/api/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      })

      const data = await res.json()

      if (!res.ok) {
        return { success: false, error: data.message || 'Login failed' }
      }

      setUser(data.user)
      localStorage.setItem('user', JSON.stringify(data.user))
      localStorage.setItem('token', data.token)

      return { success: true }
    } catch (err) {
      console.error(err)
      return { success: false, error: 'Network error - is backend running on ' + API_URL + '?' }
    }
  }

  const signup = async (email, password, name) => {
    try {
      const res = await fetch(`${API_URL}/api/auth/register`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password, name })
      })

      const data = await res.json()

      if (!res.ok) {
        return { success: false, error: data.message || 'Signup failed' }
      }

      setUser(data.user)
      localStorage.setItem('user', JSON.stringify(data.user))
      localStorage.setItem('token', data.token)

      return { success: true }
    } catch (err) {
      console.error(err)
      return { success: false, error: 'Network error' }
    }
  }

  const forgotPassword = async (email) => {
    try {
      const res = await fetch(`${API_URL}/api/auth/forgot-password`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email })
      })

      const data = await res.json()

      if (!res.ok) {
        return { success: false, error: data.message || 'Failed to send email' }
      }

      console.log('Reset link:', data.resetLink) // will show in console for testing
      return {
        success: true,
        message: data.message,
        resetLink: data.resetLink
      }
    } catch (err) {
      console.error(err)
      return { success: false, error: 'Network error - backend not running?' }
    }
  }

  const resetPassword = async (token, newPassword) => {
    try {
      const res = await fetch(`${API_URL}/api/auth/reset-password`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token, password: newPassword })
      })

      const data = await res.json()

      if (!res.ok) {
        return { success: false, error: data.message || 'Reset failed' }
      }

      return { success: true, message: data.message }
    } catch (err) {
      console.error(err)
      return { success: false, error: 'Network error' }
    }
  }

  const logout = () => {
    setUser(null)
    localStorage.removeItem('token')
    localStorage.removeItem('user')
  }

  return (
    <AuthContext.Provider value={{
      user,
      login,
      signup,
      logout,
      forgotPassword,
      resetPassword,
      loading
    }}>
      {children}
    </AuthContext.Provider>
  )
}