import LegalLayout from "../components/LegalLayout"

export default function PrivacyPolicy() {
  return (
    <LegalLayout title="Privacy Policy">

      <section>
        <h2 className="text-2xl font-semibold mb-3 text-cyan-400">
          Information We Collect
        </h2>
        <p className="text-gray-300 leading-relaxed">
          We collect your name, phone number, project details, and location 
          submitted through demo forms. This data helps us automate lead handling.
        </p>
      </section>

      <section>
        <h2 className="text-2xl font-semibold mb-3 text-cyan-400">
          How We Use Your Data
        </h2>
        <p className="text-gray-300 leading-relaxed">
          Data is used to schedule demos, automate AI qualification calls, 
          and improve service performance.
        </p>
      </section>

      <section>
        <h2 className="text-2xl font-semibold mb-3 text-cyan-400">
          Data Security
        </h2>
        <p className="text-gray-300 leading-relaxed">
          All information is transmitted via secure encrypted channels. 
          We do not sell or share user data with third parties.
        </p>
      </section>

      <section>
        <h2 className="text-2xl font-semibold mb-3 text-cyan-400">
          Contact
        </h2>
        <p className="text-gray-300">
          For privacy concerns: support@salessetu.in
        </p>
      </section>

    </LegalLayout>
  )
}