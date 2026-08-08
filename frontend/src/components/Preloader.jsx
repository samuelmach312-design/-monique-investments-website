import { useState, useEffect } from 'react'

export default function Preloader() {
  const [loading, setLoading] = useState(true)
  const [fadeOut, setFadeOut] = useState(false)

  useEffect(() => {
    // Wait for page to fully load
    const handleLoad = () => {
      setTimeout(() => {
        setFadeOut(true)
        setTimeout(() => setLoading(false), 500) // Match fade duration
      }, 800) // Show splash for at least 800ms
    }

    if (document.readyState === 'complete') {
      handleLoad()
    } else {
      window.addEventListener('load', handleLoad)
      return () => window.removeEventListener('load', handleLoad)
    }
  }, [])

  if (!loading) return null

  return (
    <div 
      className={`fixed inset-0 z-9999 flex items-center justify-center bg-[#1f1f1f] transition-opacity duration-500 ${
        fadeOut ? 'opacity-0' : 'opacity-100'
      }`}
    >
      <div className="flex flex-col items-center gap-6">
        {/* Logo with pulse animation */}
        <div className="relative">
          <img 
            src="/logo.png" 
            alt="Monique" 
            className="w-24 h-24 object-contain animate-pulse"
          />
          {/* Glowing ring */}
          <div className="absolute inset-0 rounded-full border-2 border-white/10 animate-ping" />
        </div>

        {/* Brand name */}
        <div className="text-center">
          <h1 className="text-white font-bold text-3xl tracking-wider">
            MONIQUE
          </h1>
          <p className="text-[#a0a0a0] text-xs uppercase tracking-[0.2em] mt-1">
            Luxury Footwear
          </p>
        </div>

        {/* Loading bar */}
        <div className="w-48 h-0.5 bg-[#3a3a3a] rounded-full overflow-hidden">
          <div className="h-full bg-white rounded-full animate-loading-bar" />
        </div>
      </div>
    </div>
  )
}