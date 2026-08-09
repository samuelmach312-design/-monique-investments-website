// Minimal service worker for PWA install prompt
// No caching - just meets Chrome installability requirements

self.addEventListener('install', () => {
  // Activate new SW immediately, don't wait for tabs to close
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  // Take control of all pages immediately after activation
  event.waitUntil(clients.claim());
});

self.addEventListener('fetch', () => {
  // Required by Chrome to consider the SW functional
  // Basic pass-through to network, no caching
});