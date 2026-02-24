import LegalLayout from "../components/LegalLayout"

export default function Terms() {
  return (
    <LegalLayout title="Terms & Conditions">

      <section>
        <h2 className="text-2xl font-semibold mb-3 text-cyan-400">
          Service Overview
        </h2>
        <p className="text-gray-300 leading-relaxed">
          SalesSetu provides AI-powered real estate lead automation solutions.
        </p>
      </section>

      <section>
        <h2 className="text-2xl font-semibold mb-3 text-cyan-400">
          User Responsibility
        </h2>
        <p className="text-gray-300 leading-relaxed">
          Users are responsible for how leads are handled after assignment.
        </p>
      </section>

      <section>
        <h2 className="text-2xl font-semibold mb-3 text-cyan-400">
          Limitation of Liability
        </h2>
        <p className="text-gray-300 leading-relaxed">
          SalesSetu is not liable for business results generated from platform usage.
        </p>
      </section>

    </LegalLayout>
  )
}