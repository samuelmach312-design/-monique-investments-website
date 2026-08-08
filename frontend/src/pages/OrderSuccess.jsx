import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { CheckCircle2, Copy, Loader2 } from 'lucide-react'

export default function OrderSuccess() {
  const navigate = useNavigate()
  const [order, setOrder] = useState(null)
  const [copied, setCopied] = useState(false)
  const [confirming, setConfirming] = useState(false)
  const [paid, setPaid] = useState(false)
  const PAYBILL_NUMBER = '507900'
  const ACCOUNT_NUMBER = '2016253'

  useEffect(() => {
    const lastOrder = localStorage.getItem('lastOrder')
    if (!lastOrder) return navigate('/')

    const parsed = JSON.parse(lastOrder)
    setOrder(parsed)
    setPaid(parsed.paid || false) // Load paid status if exists
  }, [navigate])

  const copyPaybill = () => {
    navigator.clipboard.writeText(PAYBILL_NUMBER)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  const confirmPayment = async () => {
    setConfirming(true)
    const timestamp = new Date().toLocaleString('en-KE', {
      timeZone: 'Africa/Nairobi',
      dateStyle: 'medium',
      timeStyle: 'short'
    })

    try {
      await fetch('/api/callmebot', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          message: `💰 PAYMENT CONFIRMED\n\nOrder: ${order.id}\nAmount: KSh ${order.total.toLocaleString()}\nCustomer: ${order.customer.name}\nPhone: ${order.customer.phone}\nEmail: ${order.customer.email}\n\nPaid at: ${timestamp}\n\nPaybill: ${PAYBILL_NUMBER}\nAccount: ${ACCOUNT_NUMBER}\nStatus: Awaiting M-Pesa verification\n\nDelivery: ${order.customer.address}, ${order.customer.city}`
        })
      })

      // Save paid status to localStorage
      const updatedOrder = {...order, paid: true, paidAt: timestamp }
      localStorage.setItem('lastOrder', JSON.stringify(updatedOrder))
      setPaid(true)

    } catch (err) {
      console.error('Failed to send confirmation:', err)
      alert('Failed to notify. Contact us directly on WhatsApp.')
    } finally {
      setConfirming(false)
    }
  }

  if (!order) return null

  return (
    <div className="min-h-screen bg-[#1f1f1f] flex items-center justify-center p-4">
      <div className="max-w-md w-full bg-[#2a2a2a] border border-[#3a3a3a] rounded-xl p-8 text-center">
        <CheckCircle2 size={64} className="text-green-400 mx-auto mb-4" />
        <h1 className="text-2xl font-bold text-white mb-2">Order Placed!</h1>
        <p className="text-[#a0a0a0] mb-6">Order #{order.id} confirmed</p>

        <div className="bg-[#1f1f1f] border border-[#3a3a3a] rounded-lg p-6 mb-6">
          <p className="text-[#b0b0b0] text-sm mb-2">Pay via M-Pesa Paybill</p>
          <div className="flex items-center justify-center gap-3 mb-2">
            <span className="text-3xl font-bold text-white tracking-wider">{PAYBILL_NUMBER}</span>
            <button
              onClick={copyPaybill}
              className="p-2 bg-[#3a3a3a] hover:bg-[#4a4a4a] rounded-lg transition-colors"
              aria-label="Copy paybill number"
            >
              <Copy size={18} className="text-white" />
            </button>
          </div>
          {copied && <p className="text-green-400 text-xs mb-2">Copied!</p>}

          <div className="text-left text-sm space-y-1 text-[#a0a0a0]">
            <p><span className="text-white">Business No:</span> {PAYBILL_NUMBER}</p>
            <p><span className="text-white">Account No:</span> {ACCOUNT_NUMBER}</p>
            <p><span className="text-white">Amount:</span> KSh {order.total.toLocaleString()}</p>
          </div>
        </div>

        <p className="text-[#a0a0a0] text-sm mb-4">
          Go to M-Pesa {'>'} Lipa Na M-Pesa {'>'} Pay Bill {'>'} Enter Business No {PAYBILL_NUMBER} {'>'} Account No {ACCOUNT_NUMBER} {'>'} Amount {'>'} PIN
        </p>

        {!paid? (
          <button
            onClick={confirmPayment}
            disabled={confirming}
            className="w-full py-3 bg-green-600 text-white font-semibold rounded-lg hover:bg-green-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2 mb-4"
          >
            {confirming && <Loader2 size={18} className="animate-spin" />}
            {confirming? 'Confirming...' : "I've Paid"}
          </button>
        ) : (
          <div className="bg-green-900/30 border border-green-700 rounded-lg p-3 mb-4">
            <p className="text-green-400 text-sm">✓ Payment notification sent</p>
            <p className="text-green-300 text-xs mt-1">We'll verify and ship your order</p>
          </div>
        )}

        <p className="text-yellow-400 text-xs mb-6">
          We'll confirm your payment and ship your order. Delivery in 1-3 days.
        </p>

        <button
          onClick={() => navigate('/')}
          className="w-full py-3 bg-[#000000] text-white font-semibold rounded-lg hover:bg-[#1a1a1a] transition-colors"
        >
          Continue Shopping
        </button>
      </div>
    </div>
  )
}
