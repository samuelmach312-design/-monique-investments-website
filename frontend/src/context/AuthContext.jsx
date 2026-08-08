import { createContext, useContext, useState, useEffect } from 'react'

const AuthContext = createContext()

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider')
  }
  return context
}

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
      // Mock login - accept any email/password for testing
      await new Promise(r => setTimeout(r, 500))

      if (!email ||!password) {
        return { success: false, error: 'Email and password required' }
      }

      const mockUser = {
        id: Date.now(),
        name: email.split('@')[0],
        email
      }

      const token = 'mock_token_' + Date.now()
      setUser(mockUser)
      localStorage.setItem('user', JSON.stringify(mockUser))
      localStorage.setItem('token', token)

      return { success: true }
    } catch (err) {
      return {
        success: false,
        error: 'Login failed. Please try again.'
      }
    }
  }

  const signup = async (email, password, name) => {
    try {
      // Mock signup - accept any details
      await new Promise(r => setTimeout(r, 500))

      if (!name ||!email ||!password) {
        return { success: false, error: 'All fields required' }
      }

      if (password.length < 6) {
        return { success: false, error: 'Password must be at least 6 characters' }
      }

      const mockUser = {
        id: Date.now(),
        name,
        email
      }

      const token = 'mock_token_' + Date.now()
      setUser(mockUser)
      localStorage.setItem('user', JSON.stringify(mockUser))
      localStorage.setItem('token', token)

      return { success: true }
    } catch (err) {
      return {
        success: false,
        error: 'Signup failed. Please try again.'
      }
    }
  }

  const forgotPassword = async (email) => {
    // Mock - just return success for testing
    await new Promise(r => setTimeout(r, 500))

    if (!email) {
      return { success: false, error: 'Email required' }
    }

    return {
      success: true,
      message: 'If this email exists, a reset link was sent to your inbox',
      resetLink: '#mock-reset-link'
    }
  }

  const resetPassword = async (token, newPassword) => {
    // Mock - just return success
    await new Promise(r => setTimeout(r, 500))

    if (!newPassword || newPassword.length < 6) {
      return { success: false, error: 'Password must be at least 6 characters' }
    }

    return { success: true, message: 'Password reset successful. You can now log in.' }
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
