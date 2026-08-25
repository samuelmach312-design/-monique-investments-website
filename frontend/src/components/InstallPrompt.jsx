import React, { useState, useEffect } from 'react'
import { X, Download, Smartphone } from 'lucide-react'
import './InstallPrompt.css'

export default function InstallPrompt() {
  const [deferredPrompt, setDeferredPrompt] = useState(null)
  const [showPrompt, setShowPrompt] = useState(false)
  const [isIOS, setIsIOS] = useState(false)

  useEffect(() => {
    const isIOSDevice = /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream
    setIsIOS(isIOSDevice)

    const handler = (e) => {
      e.preventDefault()
      setDeferredPrompt(e)
      
      const dismissed = localStorage.getItem('pwa-install-dismissed')
      const dismissedTime = localStorage.getItem('pwa-install-dismissed-time')
      const isStandalone = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone
      
      // Show again after 7 days if dismissed
      const shouldShow = !isStandalone && (!dismissed || (dismissedTime && Date.now() - Number(dismissedTime) > 7 * 24 * 60 * 60 * 1000))
      
      if (shouldShow) {
        setTimeout(() => setShowPrompt(true), 4000)
      }
    }

    const checkIOS = () => {
      const dismissed = localStorage.getItem('pwa-install-dismissed')
      const isStandalone = window.navigator.standalone
      if (isIOSDevice && !isStandalone && !dismissed) {
        setTimeout(() => setShowPrompt(true), 4000)
      }
    }

    window.addEventListener('beforeinstallprompt', handler)
    if (isIOSDevice) checkIOS()

    return () => window.removeEventListener('beforeinstallprompt', handler)
  }, [])

  const handleInstall = async () => {
    if (isIOS) {
      // iOS manual instructions
      setShowPrompt(false)
      return
    }
    if (!deferredPrompt) return
    deferredPrompt.prompt()
    const { outcome } = await deferredPrompt.userChoice
    console.log('Install outcome:', outcome)
    setDeferredPrompt(null)
    setShowPrompt(false)
    localStorage.removeItem('pwa-install-dismissed')
  }

  const handleDismiss = () => {
    localStorage.setItem('pwa-install-dismissed', 'true')
    localStorage.setItem('pwa-install-dismissed-time', Date.now().toString())
    setShowPrompt(false)
  }

  if (!showPrompt) return null

  return (
    <>
      <div className="install-backdrop" onClick={handleDismiss} />
      
      <div className="install-prompt">
        <button onClick={handleDismiss} aria-label="Close" className="install-close">
          <X size={18} />
        </button>

        <div className="install-content">
          <div className="install-icon">
            <img
              src="/images/monique-logo.png"
              alt="Monique"
              onError={(e) => { e.target.style.display='none'; e.target.nextElementSibling.style.display='flex' }}
            />
            <div className="install-icon-fallback">M</div>
          </div>

          <div className="install-text">
            <div className="install-brand">
              <div className="install-brand-name">MONIQUE INVESTMENTS</div>
              <div className="install-brand-verified">
                <div className="install-dot"></div> Official Store
              </div>
            </div>

            <h4 className="install-title">{isIOS ? 'Add to Home Screen' : 'Install Our App'}</h4>
            <p className="install-desc">
              {isIOS 
                ? 'Tap Share button → Add to Home Screen for faster shopping.'
                : 'Install for faster checkout, offline browsing & exclusive offers.'}
            </p>

            <div className="install-actions">
              <button onClick={handleInstall} className="install-btn-primary">
                {isIOS ? <Smartphone size={16} /> : <Download size={16} />}
                {isIOS ? 'How to Install' : 'Install App'}
              </button>
              <button onClick={handleDismiss} className="install-btn-secondary">
                Not Now
              </button>
            </div>

            <div className="install-benefits">
              <span>✓ Faster</span>
              <span>✓ Offline</span>
              <span>✓ No Data Cost</span>
            </div>
          </div>
        </div>
      </div>
    </>
  )
}