import { useState } from 'react';

export default function AuthModal({ mode, onClose, onSuccess }) {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const API_URL = window.location.hostname === "localhost"
   ? "http://localhost:3001"
    : "https://moniqueinvestments.digital";

  const handleSubmit = async (e) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    const endpoint = mode === 'login'? '/api/login' : '/api/register';
    const payload = mode === 'login'
     ? { email, password }
      : { name, email, password };

    try {
      const res = await fetch(`${API_URL}${endpoint}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error || 'Authentication failed');
        setLoading(false);
        return;
      }

      localStorage.setItem('token', data.token);
      localStorage.setItem('user', JSON.stringify(data.user));
      onSuccess(data.user);
      onClose();
    } catch (err) {
      setError('Server error. Try again.');
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-10000 p-5" onClick={onClose}>
      <div className="bg-white p-8 rounded-2xl max-w-md w-full" onClick={e => e.stopPropagation()}>
        <h2 className="text-2xl font-bold mb-5">{mode === 'login'? 'Login' : 'Create Account'}</h2>

        {error && <div className="bg-red-50 text-red-600 p-3 rounded-lg mb-4 text-sm">{error}</div>}

        <form onSubmit={handleSubmit} className="grid gap-4">
          {mode === 'signup' && (
            <input
              type="text"
              value={name}
              onChange={e => setName(e.target.value)}
              placeholder="Full Name"
              required
              className="w-full px-4 py-3 border border-gray-200 rounded-lg focus:border-[#e93a0e] focus:ring-2 focus:ring-[#e93a0e]/10 outline-none"
            />
          )}
          <input
            type="email"
            value={email}
            onChange={e => setEmail(e.target.value)}
            placeholder="Email"
            required
            className="w-full px-4 py-3 border border-gray-200 rounded-lg focus:border-[#e93a0e] focus:ring-2 focus:ring-[#e93a0e]/10 outline-none"
          />
          <input
            type="password"
            value={password}
            onChange={e => setPassword(e.target.value)}
            placeholder="Password"
            required
            className="w-full px-4 py-3 border border-gray-200 rounded-lg focus:border-[#e93a0e] focus:ring-2 focus:ring-[#e93a0e]/10 outline-none"
          />

          <div className="flex gap-3 mt-2">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 py-3 rounded-lg bg-gray-100 text-gray-700 font-bold hover:bg-gray-200"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={loading}
              className="flex-1 py-3 rounded-lg bg-[#e93a0e] text-white font-bold hover:bg-[#c72c06] disabled:bg-gray-300"
            >
              {loading? 'Loading...' : 'Continue'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}