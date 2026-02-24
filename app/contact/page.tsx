import LegalLayout from "../components/LegalLayout"

export default function Contact() {
  return (
    <LegalLayout title="Contact Us">

      <section>
        <h2 className="text-2xl font-semibold mb-3 text-cyan-400">
          General Inquiries
        </h2>
        <p className="text-gray-300">
          Email: support@salessetu.in
        </p>
      </section>

      <section>
        <h2 className="text-2xl font-semibold mb-3 text-cyan-400">
          Company
        </h2>
        <p className="text-gray-300">
          SalesSetu – A Product of Digital Avalokan AI  
          India
        </p>
      </section>

    </LegalLayout>
  )
}