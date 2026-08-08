import React from 'react'
import { Link } from 'react-router-dom'

export default function Footer() {
  return (
    <footer className="bg-black border-t border-gray-800 mt-auto">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
          <div>
            <h3 className="text-lg font-bold text-white mb-4">Monique Investments</h3>
            <p className="text-sm text-gray-400">Premium footwear for every step.</p>
            <p className="text-sm text-gray-400 mt-2">Premium shoes delivered across Kenya</p>
          </div>

          <div>
            <h4 className="font-semibold text-white mb-4">Contact</h4>
            <p className="text-sm text-gray-400">Kangema, Central Province, KE</p>
            <p className="text-sm text-gray-400 mt-2">
              <a href="mailto:support@monique.co.ke" className="hover:text-white transition-colors">
                support@monique.co.ke
              </a>
            </p>
            <p className="text-sm text-gray-400 mt-2">
              <a href="tel:+254748440035" className="hover:text-white transition-colors">
                +254 748 440 035
              </a>
            </p>
          </div>
        </div>

        <div className="border-t border-gray-800 mt-8 pt-8">
          <div className="flex flex-col md:flex-row justify-between items-center gap-4">
            <div className="text-sm text-gray-500">
              © 2026 Monique Investments. All rights reserved.
            </div>
            <div className="flex gap-6 text-sm">
              <Link to="/privacy" className="text-gray-400 hover:text-white transition-colors">
                Privacy Policy
              </Link>
              <Link to="/terms" className="text-gray-400 hover:text-white transition-colors">
                Terms of Service
              </Link>
              <Link to="/contact" className="text-gray-400 hover:text-white transition-colors">
                Contact Us
              </Link>
            </div>
          </div>
        </div>
      </div>
    </footer>
  )
}
