import React from 'react'
import { Phone, Mail, MapPin, MessageCircle } from 'lucide-react'

export default function Contact() {
  return (
    <div className="min-h-screen bg-[#f5f5f7] p-4 md:p-8">
      <div className="max-w-4xl mx-auto bg-white p-6 md:p-12 rounded-xl border border-gray-200">
        <h1 className="text-3xl font-bold text-gray-900 mb-2">Contact Us</h1>
        <p className="text-gray-600 mb-8">We're here to help. Reach out anytime.</p>
        
        <div className="grid md:grid-cols-2 gap-8">
          <div className="space-y-6">
            <div className="flex items-start gap-4">
              <div className="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center shrink-0">
                <MapPin className="text-gray-900" size={24} />
              </div>
              <div>
                <h3 className="font-semibold text-gray-900 mb-1">Location</h3>
                <p className="text-gray-600">chuka town, Eastern Province</p>
                <p className="text-gray-600">Kenya</p>
              </div>
            </div>

            <div className="flex items-start gap-4">
              <div className="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center shrink-0">
                <Phone className="text-gray-900" size={24} />
              </div>
              <div>
                <h3 className="font-semibold text-gray-900 mb-1">Phone</h3>
                <a href="tel:+254723808067" className="text-gray-600 hover:text-gray-900 transition-colors">
                  +254 723 808 067
                </a>
                <p className="text-sm text-gray-500 mt-1">Mon - Sat, 8AM - 6PM</p>
              </div>
            </div>

            <div className="flex items-start gap-4">
              <div className="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center shrink-0">
                <Mail className="text-gray-900" size={24} />
              </div>
              <div>
                <h3 className="font-semibold text-gray-900 mb-1">Email</h3>
                <a href="mailto:support@monique.co.ke" className="text-gray-600 hover:text-gray-900 transition-colors">
                  support@monique.co.ke
                </a>
                <p className="text-sm text-gray-500 mt-1">We reply within 24 hours</p>
              </div>
            </div>

            <div className="flex items-start gap-4">
              <div className="w-12 h-12 bg-gray-100 rounded-lg flex items-center justify-center shrink-0">
                <MessageCircle className="text-gray-900" size={24} />
              </div>
              <div>
                <h3 className="font-semibold text-gray-900 mb-1">WhatsApp</h3>
                <a 
                  href="https://wa.me/254723808067" 
                  target="_blank" 
                  rel="noopener noreferrer"
                  className="text-gray-600 hover:text-gray-900 transition-colors"
                >
                  +254 723 808 067
                </a>
                <p className="text-sm text-gray-500 mt-1">Fastest response time</p>
              </div>
            </div>
          </div>

          <div className="bg-gray-50 p-6 rounded-lg border border-gray-200">
            <h3 className="font-semibold text-gray-900 mb-4">Business Hours</h3>
            <div className="space-y-3 text-sm">
              <div className="flex justify-between">
                <span className="text-gray-600">Monday - Friday</span>
                <span className="font-medium text-gray-900">8:00 AM - 6:00 PM</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-600">Saturday</span>
                <span className="font-medium text-gray-900">9:00 AM - 4:00 PM</span>
              </div>
              <div className="flex justify-between">
                <span className="text-gray-600">Sunday</span>
                <span className="font-medium text-gray-900">Closed</span>
              </div>
            </div>

            <div className="mt-6 pt-6 border-t border-gray-200">
              <h4 className="font-semibold text-gray-900 mb-3">Free Pickup</h4>
              <p className="text-sm text-gray-600">
                chuka town pickup is free. Contact us on WhatsApp to arrange.
              </p>
            </div>

            <a
              href="https://wa.me/254723808067"
              target="_blank"
              rel="noopener noreferrer"
              className="mt-6 w-full flex items-center justify-center gap-2 px-4 py-3 bg-green-600 text-white rounded-lg font-semibold hover:bg-green-700 transition-all"
            >
              <MessageCircle size={20} />
              Chat on WhatsApp
            </a>
          </div>
        </div>
      </div>
    </div>
  )
}
