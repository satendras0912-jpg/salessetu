import Link from "next/link";

export default function Footer() {
  return (
    <footer className="bg-[#0A0A0A] border-t border-gray-800 mt-24">
      
      <div className="max-w-6xl mx-auto px-6 py-14 grid md:grid-cols-3 gap-12">

        {/* Brand Section */}
        <div>
          <h3 className="text-xl font-semibold text-white">
            SalesSetu
          </h3>
          <p className="text-gray-400 mt-4 text-sm leading-relaxed">
            AI-powered lead automation platform built for real estate
            developers and sales teams.
          </p>

          <p className="text-gray-500 text-sm mt-6">
            A Product of{" "}
            <span className="text-cyan-400 font-medium">
              Digital Avalokan AI
            </span>
          </p>
        </div>

        {/* Quick Links */}
        <div>
          <h4 className="text-white font-medium mb-4">
            Legal
          </h4>

          <div className="flex flex-col space-y-3 text-sm">
            <Link
              href="/privacy-policy"
              className="text-gray-400 hover:text-cyan-400 transition duration-300"
            >
              Privacy Policy
            </Link>

            <Link
              href="/terms"
              className="text-gray-400 hover:text-cyan-400 transition duration-300"
            >
              Terms & Conditions
            </Link>

            <Link
              href="/contact"
              className="text-gray-400 hover:text-cyan-400 transition duration-300"
            >
              Contact
            </Link>
          </div>
        </div>

        {/* Contact / CTA */}
        <div>
          <h4 className="text-white font-medium mb-4">
            Get Started
          </h4>

          <p className="text-gray-400 text-sm mb-6">
            Automate your lead follow-up and close more deals in 30 seconds.
          </p>

          <a
            href="#demo"
            className="inline-block bg-cyan-500 hover:bg-cyan-600 text-black px-6 py-3 rounded-lg text-sm font-medium transition duration-300"
          >
            Book Demo
          </a>
        </div>

      </div>

      {/* Bottom Bar */}
      <div className="border-t border-gray-800">
        <div className="max-w-6xl mx-auto px-6 py-6 flex flex-col md:flex-row justify-between items-center text-gray-500 text-xs">

          <p>
            © {new Date().getFullYear()} SalesSetu. All rights reserved.
          </p>

          <p className="mt-2 md:mt-0">
            Built with AI for modern sales teams.
          </p>

        </div>
      </div>

    </footer>
  );
}