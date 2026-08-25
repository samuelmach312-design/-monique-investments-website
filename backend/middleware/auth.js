// middleware/auth.js - MONIQUE ADMINS ONLY
// Samuel: 0706631292 -> 254706631292
// Monicah: 0723808067 -> 254723808067

const ALLOWED = ['254706631292', '254723808067', '0706631292', '0723808067'];

function normalizePhone(phone = '') {
  let p = String(phone).replace(/\s+/g, '').replace('+', '').trim();
  if (p.startsWith('0')) p = '254' + p.slice(1);
  if (p.startsWith('7') && p.length === 9) p = '254' + p;
  return p;
}

const checkAdmin = (req, res, next) => {
  // Allow GET for public store
  if (req.method === 'GET') return next();

  const rawPhone = req.headers['x-admin-phone'] || req.body?.adminPhone || '';
  const phone = normalizePhone(rawPhone);

  if (!ALLOWED.includes(phone) && !ALLOWED.includes(rawPhone)) {
    console.log(`BLOCKED ADMIN ATTEMPT: ${rawPhone} -> ${phone}`);
    return res.status(403).json({ 
      success: false,
      error: 'Not authorized - Monique Admins only. Samuel & Monicah only.' 
    });
  }

  // Attach admin info
  req.admin = phone === '254706631292' || rawPhone === '0706631292' 
    ? { name: 'Samuel', phone: '0706631292' } 
    : { name: 'Monicah', phone: '0723808067' };
  
  next();
};

module.exports = { checkAdmin, normalizePhone, ALLOWED };