import DemoForm from "../components/DemoForm";
import Footer from "./components/Footer";

export default function Home() {
  return (
    <main className="bg-[#0A0A0A] text-white">

      {/* HERO SECTION */}
      <section className="min-h-screen flex items-center px-6 py-20">
        <div className="max-w-6xl mx-auto grid md:grid-cols-2 gap-12 items-center">

          <div>
            <div className="inline-block bg-cyan-500/10 border border-cyan-500/30 text-cyan-400 px-4 py-2 rounded-full text-sm mb-6">
              AI Powered Real Estate Automation
            </div>

            <h1 className="text-4xl md:text-6xl font-bold leading-tight">
              Convert Real Estate Leads
              <span className="block text-cyan-400 mt-2">
                Automatically in 30 Seconds
              </span>
            </h1>

            <p className="mt-6 text-lg text-gray-400 max-w-xl">
              SalesSetu instantly calls, qualifies, and nurtures every property lead.
              Your sales team only speaks to serious buyers.
            </p>

            <div className="mt-8 flex gap-4 flex-wrap">
              <a
  href="#demo"
  className="bg-cyan-500 px-6 py-3 rounded-xl font-semibold"
>
  Book Live Demo
</a>

              <a
  href="#how-it-works"
  className="border border-gray-700 px-6 py-3 rounded-xl"
>
  See How It Works
</a>
            </div>
          </div>

          <div className="bg-[#111111] border border-gray-800 rounded-2xl p-8 shadow-2xl">
            <p className="text-gray-500 text-sm mb-6">
              Automated Lead Flow
            </p>

            <div className="space-y-4 text-sm">
              <div className="bg-[#1A1A1A] p-4 rounded-lg">
                📥 Meta / Google Lead Captured
              </div>

              <div className="bg-[#1A1A1A] p-4 rounded-lg">
                🤖 AI Qualification Call
              </div>

              <div className="bg-[#1A1A1A] p-4 rounded-lg">
                💬 WhatsApp Nurturing
              </div>

              <div className="bg-cyan-500 text-black p-4 rounded-lg font-semibold">
                🔥 HOT Lead → Assigned to Agent
              </div>
            </div>
          </div>

        </div>
      </section>

      {/* PROBLEM SECTION */}
      <section className="py-20 px-6 bg-[#111111]">
        <div className="max-w-6xl mx-auto text-center">

          <h2 className="text-3xl md:text-4xl font-bold mb-6">
            Real Estate Leads Are Being Wasted Every Day
          </h2>

          <p className="text-gray-400 max-w-2xl mx-auto mb-16">
            Most brokers respond after 15–30 minutes. By then, the buyer has already moved to another project.
            Speed decides who closes the deal.
          </p>

          <div className="grid md:grid-cols-3 gap-8 text-left">

            <div className="bg-[#1A1A1A] p-8 rounded-xl border border-gray-800">
              <h3 className="text-xl font-semibold mb-4 text-red-400">
                ⏳ Slow Response
              </h3>
              <p className="text-gray-400">
                Leads wait too long before first contact. Interest drops quickly.
              </p>
            </div>

            <div className="bg-[#1A1A1A] p-8 rounded-xl border border-gray-800">
              <h3 className="text-xl font-semibold mb-4 text-red-400">
                📞 Manual Follow-up
              </h3>
              <p className="text-gray-400">
                Agents waste time calling unqualified or fake inquiries.
              </p>
            </div>

            <div className="bg-[#1A1A1A] p-8 rounded-xl border border-gray-800">
              <h3 className="text-xl font-semibold mb-4 text-red-400">
                💸 Low Conversion Rate
              </h3>
              <p className="text-gray-400">
                Without automation, most marketing spend turns into lost opportunities.
              </p>
            </div>

          </div>
        </div>
      </section>

      {/* SOLUTION SECTION */}
<section className="py-20 px-6 bg-[#0A0A0A]">
  <div className="max-w-6xl mx-auto grid md:grid-cols-2 gap-16 items-center">

    {/* LEFT VISUAL */}
    <div className="relative">
  <div className="absolute -inset-4 bg-cyan-500/10 blur-3xl rounded-3xl pointer-events-none"></div>

      <div className="relative z-10 bg-[#111111] border border-gray-800 rounded-2xl p-8 space-y-6">
        <div className="flex justify-between items-center text-sm text-gray-400">
          <span>New Lead Received</span>
          <span>00:00 sec</span>
        </div>

        <div className="bg-[#1A1A1A] p-4 rounded-lg text-sm">
          🤖 AI Calling Lead...
        </div>

        <div className="bg-[#1A1A1A] p-4 rounded-lg text-sm">
          📊 Budget: ₹80L – ₹1Cr
        </div>

        <div className="bg-[#1A1A1A] p-4 rounded-lg text-sm">
          🏠 Location Preference: Noida
        </div>

        <div className="bg-cyan-500 text-black p-4 rounded-lg font-semibold text-sm">
          🔥 Qualified Buyer → Sent to Agent
        </div>
      </div>
    </div>

    {/* RIGHT CONTENT */}
    <div>
      <h2 className="text-3xl md:text-4xl font-bold mb-6">
        SalesSetu Responds in Seconds. Not Minutes.
      </h2>

      <p className="text-gray-400 mb-8">
        The moment a lead comes from Meta, Google, or Website —
        our AI instantly calls, qualifies, and segments the buyer.
        Your team only receives serious, ready-to-visit prospects.
      </p>

      <ul className="space-y-4 text-gray-300">
        <li>⚡ Instant AI Call within 30 seconds</li>
        <li>📈 Budget & Intent Qualification</li>
        <li>💬 Automated WhatsApp Follow-ups</li>
        <li>🔥 Only HOT Leads Assigned to Sales Team</li>
      </ul>

      <div className="mt-10">
        <a
  href="#demo"
  className="bg-cyan-500 px-6 py-3 rounded-xl"
>
  See SalesSetu in Action
</a>
      </div>
    </div>

  </div>
</section>

{/* HOW IT WORKS */}
<section id="how-it-works" className="py-20 px-6 bg-black">
  <div className="max-w-6xl mx-auto text-center">

    <h2 className="text-4xl font-bold mb-12">
      How SalesSetu Works
    </h2>

    <div className="grid md:grid-cols-4 gap-8 text-left">

      <div className="bg-[#111111] p-6 rounded-xl border border-gray-800">
        <h3 className="font-semibold mb-2 text-cyan-400">1. Lead Captured</h3>
        <p className="text-gray-400 text-sm">
          Meta Ads, Google Ads or Website forms send lead instantly.
        </p>
      </div>

      <div className="bg-[#111111] p-6 rounded-xl border border-gray-800">
        <h3 className="font-semibold mb-2 text-cyan-400">2. AI Qualification Call</h3>
        <p className="text-gray-400 text-sm">
          AI calls within 30 seconds and checks budget & intent.
        </p>
      </div>

      <div className="bg-[#111111] p-6 rounded-xl border border-gray-800">
        <h3 className="font-semibold mb-2 text-cyan-400">3. WhatsApp Nurturing</h3>
        <p className="text-gray-400 text-sm">
          Automated follow-ups build trust and filter serious buyers.
        </p>
      </div>

      <div className="bg-[#111111] p-6 rounded-xl border border-gray-800">
        <h3 className="font-semibold mb-2 text-cyan-400">4. HOT Lead to Agent</h3>
        <p className="text-gray-400 text-sm">
          Only qualified leads are assigned to your sales team.
        </p>
      </div>

    </div>

  </div>
</section>

{/* RESULTS SECTION */}
<section className="py-20 px-6 bg-[#111111]">
  <div className="max-w-6xl mx-auto text-center">

    <h2 className="text-3xl md:text-4xl font-bold mb-6">
      Real Results. Real Growth.
    </h2>

    <p className="text-gray-400 max-w-2xl mx-auto mb-16">
      SalesSetu is built to increase response speed, improve qualification,
      and maximize return on ad spend for real estate businesses.
    </p>

    <div className="grid md:grid-cols-4 gap-8">

      <div className="bg-[#1A1A1A] p-8 rounded-xl border border-gray-800">
        <h3 className="text-4xl font-bold text-cyan-400 mb-3">30s</h3>
        <p className="text-gray-400 text-sm">
          Average First Response Time
        </p>
      </div>

      <div className="bg-[#1A1A1A] p-8 rounded-xl border border-gray-800">
        <h3 className="text-4xl font-bold text-cyan-400 mb-3">3X</h3>
        <p className="text-gray-400 text-sm">
          Higher Lead Conversion
        </p>
      </div>

      <div className="bg-[#1A1A1A] p-8 rounded-xl border border-gray-800">
        <h3 className="text-4xl font-bold text-cyan-400 mb-3">60%</h3>
        <p className="text-gray-400 text-sm">
          Reduction in Manual Calls
        </p>
      </div>

      <div className="bg-[#1A1A1A] p-8 rounded-xl border border-gray-800">
        <h3 className="text-4xl font-bold text-cyan-400 mb-3">24/7</h3>
        <p className="text-gray-400 text-sm">
          AI Availability
        </p>
      </div>

    </div>
  </div>
</section>

{/* SOCIAL PROOF SECTION */}
<section className="py-20 px-6 bg-[#0A0A0A]">
  <div className="max-w-6xl mx-auto text-center">

    <h2 className="text-3xl md:text-4xl font-bold mb-6">
      Trusted by Growth-Focused Real Estate Teams
    </h2>

    <p className="text-gray-400 max-w-2xl mx-auto mb-16">
      Brokers and developers use SalesSetu to respond faster,
      qualify smarter, and close more deals.
    </p>

    <div className="grid md:grid-cols-3 gap-8 text-left">

      {/* Testimonial 1 */}
      <div className="bg-[#111111] border border-gray-800 p-8 rounded-2xl">
        <p className="text-gray-300 mb-6">
          “Earlier our team missed half the leads. Now AI responds instantly
          and we only speak to serious buyers. Conversion has improved massively.”
        </p>

        <div>
          <p className="font-semibold text-white">Amit Sharma</p>
          <p className="text-sm text-gray-500">Real Estate Developer – Noida</p>
        </div>
      </div>

      {/* Testimonial 2 */}
      <div className="bg-[#111111] border border-gray-800 p-8 rounded-2xl">
        <p className="text-gray-300 mb-6">
          “Our response time dropped from 20 minutes to under 1 minute.
          That alone changed our sales numbers.”
        </p>

        <div>
          <p className="font-semibold text-white">Ritika Jain</p>
          <p className="text-sm text-gray-500">Channel Partner – Gurgaon</p>
        </div>
      </div>

      {/* Testimonial 3 */}
      <div className="bg-[#111111] border border-gray-800 p-8 rounded-2xl">
        <p className="text-gray-300 mb-6">
          “WhatsApp nurturing is a game changer. Even cold leads
          convert after automated follow-ups.”
        </p>

        <div>
          <p className="font-semibold text-white">Rahul Verma</p>
          <p className="text-sm text-gray-500">Property Consultant – Delhi NCR</p>
        </div>
      </div>

    </div>

  </div>
</section>

{/* PRICING SECTION */}
<section className="py-28 px-6 bg-[#111111]">
  <div className="max-w-6xl mx-auto text-center">

    <h2 className="text-3xl md:text-4xl font-bold mb-6">
      Simple, Transparent Pricing
    </h2>

    <p className="text-gray-400 max-w-2xl mx-auto mb-16">
      Built for real estate teams of all sizes.
      Scale automation as your lead volume grows.
    </p>

    <div className="grid md:grid-cols-3 gap-8">

      {/* BASIC */}
      <div className="bg-[#1A1A1A] border border-gray-800 p-8 rounded-2xl">
        <h3 className="text-xl font-semibold mb-4">Starter</h3>
        <p className="text-4xl font-bold text-white mb-6">
          ₹9,999<span className="text-sm text-gray-400">/month</span>
        </p>

        <ul className="space-y-3 text-gray-400 text-sm mb-8">
          <li>✔ Up to 500 leads/month</li>
          <li>✔ AI Qualification Calls</li>
          <li>✔ WhatsApp Follow-ups</li>
          <li>✔ Basic Lead Dashboard</li>
        </ul>

        <a
  href="#demo"
  className="border border-gray-700 px-6 py-3 rounded-xl inline-block text-center hover:bg-gray-800 transition"
>
  Get Started
</a>
      </div>

      {/* PRO – HIGHLIGHTED */}
      <div className="bg-[#0A0A0A] border-2 border-cyan-500 p-8 rounded-2xl relative scale-105">

        <div className="absolute -top-4 left-1/2 -translate-x-1/2 bg-cyan-500 text-black text-xs px-4 py-1 rounded-full font-semibold">
          Most Popular
        </div>

        <h3 className="text-xl font-semibold mb-4 mt-4">Professional</h3>
        <p className="text-4xl font-bold text-cyan-400 mb-6">
          ₹19,999<span className="text-sm text-gray-400">/month</span>
        </p>

        <ul className="space-y-3 text-gray-300 text-sm mb-8">
          <li>✔ Up to 2000 leads/month</li>
          <li>✔ Advanced AI Call Scripts</li>
          <li>✔ Smart Lead Scoring</li>
          <li>✔ WhatsApp Automation + Nurturing</li>
          <li>✔ CRM Integration</li>
        </ul>

        <a
  href="#demo"
  className="bg-cyan-500 px-6 py-3 rounded-xl inline-block text-center text-black font-semibold hover:opacity-90 transition"
>
  Book Demo
</a>
      </div>

      {/* ENTERPRISE */}
      <div className="bg-[#1A1A1A] border border-gray-800 p-8 rounded-2xl">
        <h3 className="text-xl font-semibold mb-4">Enterprise</h3>
        <p className="text-4xl font-bold text-white mb-6">
          Custom
        </p>

        <ul className="space-y-3 text-gray-400 text-sm mb-8">
          <li>✔ Unlimited Leads</li>
          <li>✔ Dedicated AI Model</li>
          <li>✔ Multi-Project Setup</li>
          <li>✔ Custom CRM & API Access</li>
          <li>✔ Priority Support</li>
        </ul>

        <a
  href="#demo"
  className="border border-gray-700 px-6 py-3 rounded-xl inline-block text-center hover:bg-gray-800 transition"
>
  Contact Sales
</a>
      </div>

    </div>
  </div>
</section>

{/* FINAL CTA SECTION */}
<section className="relative z-20 py-20 px-6 bg-cyan-500 text-black text-center">
  <div className="max-w-4xl mx-auto">

    <h2 className="text-3xl md:text-5xl font-bold mb-6 leading-tight">
      Stop Losing Real Estate Leads.
      <br />
      Start Converting Them Automatically.
    </h2>

    <p className="mb-10 text-lg opacity-90">
      SalesSetu works 24/7 so your team never misses a serious buyer again.
    </p>

    <div className="flex justify-center gap-6 flex-wrap">

      <a
  href="#demo"
  className="border bg-black-500 px-6 py-3 rounded-xl"
>
  Book Live Demo
</a>

      <a
  href="https://wa.me/917060213244"
  target="_blank"
  rel="noopener noreferrer"
  className="border px-6 py-3 rounded-xl inline-block"
>
  Talk to Sales
</a>

    </div>

  </div>
</section>

{/* DEMO FORM SECTION */}
<section id="demo" className="py-20 px-6 bg-[#111111]">
  <div className="max-w-3xl mx-auto">

    <h2 className="text-3xl font-bold text-center mb-6">
      Book a Free Live Demo
    </h2>

    <p className="text-gray-400 text-center mb-12">
      See how SalesSetu can automate your real estate lead handling.
    </p>

    <DemoForm />

  </div>
</section>

<Footer />

  </main>
);
}           