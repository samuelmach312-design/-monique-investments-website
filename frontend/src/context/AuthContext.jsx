import { createContext, useContext, useState, useEffect } from 'react'

const AuthContext = createContext()

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider')
  }
  return context
}

const API_URL = import.meta.env.VITE_API_URL || 'https://monique-investments-website.onrender.com/api'

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
      const res = await fetch(`${API_URL}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password })
      })
      const data = await res.json()
      if (!res.ok) return { success: false, error: data.message || 'Login failed' }
      setUser(data.user)
      localStorage.setItem('user', JSON.stringify(data.user))
      localStorage.setItem('token', data.token)
      return { success: true }
    } catch (err) {
      return { success: false, error: 'Network error - backend sleeping, wait 50s and retry' }
    }
  }

  const signup = async (email, password, name) => {
    try {
      const res = await fetch(`${API_URL}/auth/register`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password, name })
      })
      const data = await res.json()
      if (!res.ok) return { success: false, error: data.message || 'Signup failed' }
      setUser(data.user)
      localStorage.setItem('user', JSON.stringify(data.user))
      localStorage.setItem('token', data.token)
      return { success: true }
    } catch (err) {
      return { success: false, error: 'Network error' }
    }
  }

  const forgotPassword = async (email) => {
    try {
      const res = await fetch(`${API_URL}/auth/forgot-password`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email })
      })
      const data = await res.json()
      if (!res.ok) return { success: false, error: data.message || 'Failed' }
      console.log('RESET LINK:', data.resetLink)
      return { success: true, message: data.message, resetLink: data.resetLink }
    } catch (err) {
      return { success: false, error: 'Network error - backend waking up, wait 1 min and retry!' }
    }
  }

  const resetPassword = async (token, newPassword) => {
    try {
      const res = await fetch(`${API_URL}/auth/reset-password`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ token, password: newPassword })
      })
      const data = await res.json()
      if (!res.ok) return { success: false, error: data.message || 'Reset failed' }
      return { success: true, message: data.message }
    } catch (err) {
      return { success: false, error: 'Network error' }
    }
  }

  const logout = () => {
    setUser(null)
    localStorage.removeItem('token')
    localStorage.removeItem('user')
  }

  return (
    <AuthContext.Provider value={{ user, login, signup, logout, forgotPassword, resetPassword, loading }}>
      {children}
    </AuthContext.Provider>
  )
}