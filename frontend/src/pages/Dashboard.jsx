import { useEffect } from 'react'
import { useNavigate } from 'react-router-dom'

function Dashboard() {
  const navigate = useNavigate()

  useEffect(() => {
    const token = localStorage.getItem('token')
    if (!token) {
      navigate('/login') // kick out if not logged in
    }
  }, [navigate])

  return (
    <div className="w-full min-h-screen px-4 md:px-8 py-6">
      <h1 className="text-2xl font-bold text-(--text)">Dashboard</h1>
      <p className="text-(--text-muted) mt-2">Welcome to your dashboard</p>
      {/* your dashboard content here */}
    </div>
  )
}

export default Dashboard