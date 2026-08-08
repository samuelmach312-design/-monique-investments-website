import { useState, useEffect } from 'react';

export function usePWAInstall() {
  const [installPrompt, setInstallPrompt] = useState(null);
  const [isInstalled, setIsInstalled] = useState(false);
  const [canInstall, setCanInstall] = useState(false);

  useEffect(() => {
    // Check if already installed - PWA or iOS standalone
    if (window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone) {
      setIsInstalled(true);
      return;
    }

    // Check if we cached that prompt was available before reload
    const cached = sessionStorage.getItem('pwa-prompt-available');
    if (cached === 'true') {
      setCanInstall(true);
    }

    const handleBeforeInstall = (e) => {
      e.preventDefault();
      setInstallPrompt(e);
      setCanInstall(true);
      sessionStorage.setItem('pwa-prompt-available', 'true'); // Cache for reloads
    };

    const handleAppInstalled = () => {
      setIsInstalled(true);
      setInstallPrompt(null);
      setCanInstall(false);
      sessionStorage.removeItem('pwa-prompt-available');
    };

    window.addEventListener('beforeinstallprompt', handleBeforeInstall);
    window.addEventListener('appinstalled', handleAppInstalled);

    return () => {
      window.removeEventListener('beforeinstallprompt', handleBeforeInstall);
      window.removeEventListener('appinstalled', handleAppInstalled);
    };
  }, []);

  const install = async () => {
    if (!installPrompt) return;
    
    installPrompt.prompt();
    const { outcome } = await installPrompt.userChoice;
    
    // If user dismissed, clear cache so we don't show button again
    if (outcome === 'dismissed') {
      sessionStorage.removeItem('pwa-prompt-available');
    }
    
    setInstallPrompt(null);
    setCanInstall(false);
  };

  return { installPrompt, install, isInstalled, canInstall };
}