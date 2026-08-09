export default async function handler(req, res) {
  // Allow POST (from checkout) and GET (for browser test)
  if (req.method !== 'POST' && req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' })
  }

  const message = req.body?.message || req.query?.message;
  
  // Read BOTH sets - fallback to old single var if you still use it
  const recipients = [
   { phone: (process.env.CALLMEBOT_PHONE_1 || process.env.CALLMEBOT_PHONE || '').trim(), apikey: (process.env.CALLMEBOT_APIKEY_1 || process.env.CALLMEBOT_APIKEY || '').trim() },
   { phone: (process.env.CALLMEBOT_PHONE_2 || '').trim(), apikey: (process.env.CALLMEBOT_APIKEY_2 || '').trim() },
  ].filter(r => r.phone && r.apikey);

  console.log('Recipients:', recipients.map(r=>r.phone), 'Message:', message);

  if (!message) {
    return res.status(400).json({ error: 'Missing message' });
  }

  if (recipients.length === 0) {
    return res.status(500).json({ 
      error: 'Missing config',
      debug: { 
        hasPhone1: !!process.env.CALLMEBOT_PHONE_1,
        hasKey1: !!process.env.CALLMEBOT_APIKEY_1,
        hasPhone2: !!process.env.CALLMEBOT_PHONE_2,
        hasKey2: !!process.env.CALLMEBOT_APIKEY_2,
        allCallmeVars: Object.keys(process.env).filter(k => k.includes('CALLME'))
      }
    });
  }

  try {
    const results = [];
    for (const r of recipients) {
      const url = 'https://api.callmebot.com/whatsapp.php?phone=' + r.phone + '&apikey=' + r.apikey + '&text=' + encodeURIComponent(message);
      const response = await fetch(url);
      const text = await response.text();
      console.log('CallMeBot reply for ' + r.phone + ':', text);
      
      if (text.includes('ERROR')) {
        results.push({ phone: r.phone, success: false, error: text });
      } else {
        results.push({ phone: r.phone, success: true, response: text });
      }
    }

    const anySuccess = results.some(r => r.success);
    if (!anySuccess) {
      return res.status(400).json({ error: 'All failed', results });
    }

    return res.status(200).json({ success: true, results });

  } catch (error) {
    console.error(error);
    return res.status(500).json({ error: 'Failed: ' + error.message });
  }
}