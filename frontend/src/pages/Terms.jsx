import React from 'react'

export default function Terms() {
  return (
    <div className="min-h-screen bg-[#f5f5f7] p-4 md:p-8">
      <div className="max-w-4xl mx-auto bg-white p-6 md:p-12 rounded-xl border border-gray-200">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">Terms of Service</h1>
        <p className="text-gray-500 mb-8">Last updated: June 8, 2026</p>
        
        <div className="space-y-6 text-gray-700 leading-relaxed">
          <section>
            <h2 className="text-xl font-semibold text-gray-900 mb-3">1. Orders & Payment</h2>
            <p>
              All prices are in Kenyan Shillings (KSh). Payment is via M-Pesa before shipping. 
              Orders are confirmed via WhatsApp after payment verification. Prices are subject to change without notice.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900 mb-3">2. Shipping & Delivery</h2>
            <p className="mb-3">
              We ship countrywide via courier. Delivery fees vary by location and will be communicated before payment.
            </p>
            <ul className="list-disc pl-6 space-y-2">
              <li>Nairobi: 1-2 business days</li>
              <li>Other major towns: 2-4 business days</li>
              <li>Remote areas: 3-7 business days</li>
            </ul>
            <p className="mt-3">
              Delivery times are estimates. Monique Investments is not liable for delays caused by courier services.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900 mb-3">3. No Returns or Refunds</h2>
            <p className="mb-3 font-medium text-gray-900">
              All sales are final. We do not accept returns, exchanges, or refunds once payment is made.
            </p>
            <p className="mb-3">
              Please confirm your size, color, and product details before completing your order. We recommend 
              checking our size guide and product descriptions carefully.
            </p>
            <p>
              <strong>Exception:</strong> If you receive a defective or wrong item due to our error, contact us 
              within 24 hours on WhatsApp <a href="tel:+254723808067" className="text-gray-900 font-semibold hover:underline">+254 723 808 067</a> with 
              photos for resolution. We will replace the item at no extra cost.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900 mb-3">4. Product Availability</h2>
            <p>
              All products are subject to availability. If an item is out of stock after payment, we will contact 
              you immediately to arrange a full refund or suggest an alternative.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900 mb-3">5. Limitation of Liability</h2>
            <p>
              Monique Investments shall not be liable for any indirect, incidental, or consequential damages 
              arising from the use of our products or services.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900 mb-3">6. Contact Information</h2>
            <p>
              For questions about these Terms of Service, contact us:
            </p>
            <div className="mt-3 space-y-1">
              <p><strong>Business:</strong> Monique Investments</p>
              <p><strong>Location:</strong> chuka town, Eastern Province, Kenya</p>
              <p><strong>Phone:</strong> <a href="tel:+254723808067" className="text-gray-900 font-semibold hover:underline">+254 723 808 067</a></p>
              <p><strong>Email:</strong> <a href="mailto:support@monique.co.ke" className="text-gray-900 font-semibold hover:underline">support@monique.co.ke</a></p>
            </div>
          </section>
        </div>
      </div>
    </div>
  )
}
