import { useState, useEffect } from 'react'
import { X, Download, Smartphone } from 'lucide-react'
import { usePWAInstall } from '../hooks/usePWAInstall'
import './InstallPrompt.css'

export default function InstallPrompt() {
  const { canInstall, installPrompt, install, isInstalled } = usePWAInstall()
  const [showPrompt, setShowPrompt] = useState(false)
  const [isIOS, setIsIOS] = useState(false)

  useEffect(() => {
    const isIOSDevice = /iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream
    setIsIOS(isIOSDevice)
    if (isInstalled) return

    const dismissedTime = localStorage.getItem('pwa-install-dismissed-time')
    const shouldShow = !dismissedTime || Date.now() - Number(dismissedTime) > 7 * 24 * 60 * 60 * 1000

    if ((canInstall || isIOSDevice) && shouldShow) {
      const timer = setTimeout(() => setShowPrompt(true), 4000)
      return () => clearTimeout(timer)
    }
  }, [canInstall, isInstalled])

  const handleInstall = async () => {
    if (isIOS) { setShowPrompt(false); return }
    await install()
    setShowPrompt(false)
  }

  const handleDismiss = () => {
    localStorage.setItem('pwa-install-dismissed-time', Date.now().toString())
    setShowPrompt(false)
  }

  if (!showPrompt || isInstalled) return null

  return (
    <>
      <div className="install-backdrop" onClick={handleDismiss} />
      <div className="install-prompt">
        <button onClick={handleDismiss} className="install-close"><X size={18} /></button>
        <div className="install-content">
          <div className="install-icon">
            <img src="/monique-logo-192.png" alt="Monique" />
            <div className="install-icon-fallback">M</div>
          </div>
          <div className="install-text">
            <div className="install-brand">
              <div className="install-brand-name">MONIQUE INVESTMENTS</div>
              <div className="install-brand-verified"><div className="install-dot"></div> Official Store</div>
            </div>
            <h4 className="install-title">{isIOS ? 'Add to Home Screen' : 'Install Our App'}</h4>
            <p className="install-desc">{isIOS ? 'Tap Share → Add to Home Screen for real app experience' : 'Install as real app - faster, offline, no browser bar'}</p>
            <div className="install-actions">
              <button onClick={handleInstall} className="install-btn-primary">{isIOS ? <Smartphone size={16} /> : <Download size={16} />}{isIOS ? 'How to Install' : 'Install App'}</button>
              <button onClick={handleDismiss} className="install-btn-secondary">Not Now</button>
            </div>
          </div>
        </div>
      </div>
    </>
  )
}