import React from 'react'

export default function Privacy() {
  return (
    <div className="min-h-screen bg-[#f5f5f7] p-4 md:p-8">
      <div className="max-w-4xl mx-auto bg-white p-6 md:p-12 rounded-xl border border-gray-200">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">Privacy Policy</h1>
        <p className="text-gray-500 mb-8">Last updated: June 8, 2026</p>
        
        <div className="space-y-6 text-gray-700 leading-relaxed">
          <section>
            <h2 className="text-xl font-semibold text-gray-900 mb-3">1. Information We Collect</h2>
            <p>
              Monique Investments collects your name, email, phone number, and delivery address when you place an order. 
              We use M-Pesa for payments and do not store your M-Pesa PIN or payment credentials. All payment processing 
              is handled securely by M-Pesa.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900 mb-3">2. How We Use Your Data</h2>
            <p className="mb-3">
              We use your data to process orders, deliver products, and send order updates via WhatsApp or SMS. 
              Your information helps us:
            </p>
            <ul className="list-disc pl-6 space-y-2">
              <li>Process and fulfill your orders</li>
              <li>Communicate order status and delivery updates</li>
              <li>Respond to customer service requests</li>
              <li>Improve our products and services</li>
            </ul>
            <p className="mt-3 font-medium">
              We do not sell, rent, or share your personal data with third parties for marketing purposes.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900 mb-3">3. Data Security</h2>
            <p>
              We implement appropriate security measures to protect your personal information. Your data is stored 
              securely and access is limited to authorized personnel only. However, no method of transmission over 
              the internet is 100% secure.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900 mb-3">4. Your Rights</h2>
            <p>
              You have the right to access, update, or request deletion of your personal data. Contact us if you 
              wish to review or modify your information.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900 mb-3">5. Cookies</h2>
            <p>
              We use localStorage to save your cart and login session for a better shopping experience. No third-party 
              tracking cookies are used.
            </p>
          </section>

          <section>
            <h2 className="text-xl font-semibold text-gray-900 mb-3">6. Contact Us</h2>
            <p>
              For privacy questions or concerns, contact us:
            </p>
            <div className="mt-3 space-y-1">
              <p><strong>Phone:</strong> +254 723 808 067</p>
              <p><strong>Location:</strong> chuka town, Eastern Province, Kenya</p>
              <p><strong>Email:</strong> mwangare80@gmail.com</p>
            </div>
          </section>
        </div>
      </div>
    </div>
  )
}
