import Link from "next/link";

export default function Footer() {
  return (
    <footer className="text-gray-400 py-10 border-t border-gray-800 mt-20">
      <div className="flex gap-6 justify-center text-sm">
        <Link href="/privacy-policy" className="hover:text-white transition">
          Privacy Policy
        </Link>

        <Link href="/terms" className="hover:text-white transition">
          Terms
        </Link>

        <Link href="/contact" className="hover:text-white transition">
          Contact
        </Link>
      </div>

      <div className="text-center mt-6 text-xs text-gray-500">
        © 2026 SalesSetu. A Product of Digital Avalokan AI
      </div>
    </footer>
  );
}