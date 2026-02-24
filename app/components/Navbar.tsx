"use client";

import Link from "next/link";

export default function Navbar() {
  return (
    <header className="fixed top-0 left-0 w-full z-50 bg-[#0A0A0A]/80 backdrop-blur-md border-b border-gray-800">
      <div className="max-w-6xl mx-auto px-6 py-4 flex justify-between items-center">

        {/* Logo */}
        <Link href="/" className="text-white text-xl font-semibold">
          Sales<span className="text-cyan-400">Setu</span>
        </Link>

        {/* Nav Links */}
        <nav className="hidden md:flex gap-8 text-sm text-gray-400">
          <a href="#how-it-works" className="hover:text-white transition">
            How It Works
          </a>

          <a href="#demo" className="hover:text-white transition">
            Book Demo
          </a>

          <Link href="/contact" className="hover:text-white transition">
            Contact
          </Link>
        </nav>

        {/* CTA Button */}
        <a
          href="#demo"
          className="bg-cyan-500 hover:bg-cyan-600 text-black font-medium px-5 py-2 rounded-lg transition shadow-lg shadow-cyan-500/20 text-sm"
        >
          Get Started
        </a>

      </div>
    </header>
  );
}