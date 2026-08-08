import React, { useState, useEffect } from 'react'
import { X, Download } from 'lucide-react'
import './InstallPrompt.css'

export default function InstallPrompt() {
  const [deferredPrompt, setDeferredPrompt] = useState(null)
  const [showPrompt, setShowPrompt] = useState(false)

  useEffect(() => {
    const handler = (e) => {
      e.preventDefault()
      setDeferredPrompt(e)
      
      // Don't show if already installed or dismissed before
      const dismissed = localStorage.getItem('pwa-install-dismissed')
      const isStandalone = window.matchMedia('(display-mode: standalone)').matches
      
      if (!dismissed && !isStandalone) {
        // Delay 3s so it doesn't pop immediately on load
        setTimeout(() => setShowPrompt(true), 3000)
      }
    }

    window.addEventListener('beforeinstallprompt', handler)
    return () => window.removeEventListener('beforeinstallprompt', handler)
  }, [])

  const handleInstall = async () => {
    if (!deferredPrompt) return
    
    deferredPrompt.prompt()
    const { outcome } = await deferredPrompt.userChoice
    
    if (outcome === 'accepted') {
      console.log('User installed app')
    }
    
    setDeferredPrompt(null)
    setShowPrompt(false)
  }

  const handleDismiss = () => {
    localStorage.setItem('pwa-install-dismissed', 'true')
    setShowPrompt(false)
  }

  if (!showPrompt) return null

  return (
    <>
      {/* Backdrop - mobile only */}
      <div className="install-backdrop" onClick={handleDismiss} />
      
      <div className="install-prompt">
        <button
          onClick={handleDismiss}
          aria-label="Close install prompt"
          className="install-close"
        >
          <X size={16} />
        </button>

        <div className="install-content">
          {/* Logo */}
          <div className="install-icon">
            <img
              src="/images/monique-logo.png"
              alt="Monique Investments"
              onError={(e) => { e.target.src = '/logo.png' }}
            />
          </div>

          <div className="install-text">
            <div className="install-brand">
              <div className="install-brand-name">MONIQUE</div>
              <div className="install-brand-sub">INVESTMENTS</div>
            </div>

            <h4 className="install-title">Install App</h4>
            <p className="install-desc">
              Add to your home screen for faster access and offline browsing.
            </p>

            <div className="install-actions">
              <button
                onClick={handleInstall}
                className="install-btn-primary"
              >
                <Download size={16} />
                Install
              </button>
              <button
                onClick={handleDismiss}
                className="install-btn-secondary"
              >
                Later
              </button>
            </div>
          </div>
        </div>

        {/* Trust indicator */}
        <div className="install-footer">
          <div className="install-dot"></div>
          <span>Official App • No signup required</span>
        </div>
      </div>
    </>
  )
}

