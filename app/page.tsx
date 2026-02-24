import DemoForm from "../components/DemoForm";
import Footer from "./components/Footer";
import Navbar from "./components/Navbar";

export default function Home() {
  return (
    <>
    <Navbar />
    <main className="bg-[#0A0A0A] text-white">

      {/* HERO SECTION */}
      <section className="min-h-screen flex items-center pt-32 px-6 bg-[#0A0A0A]">
  <div className="max-w-6xl mx-auto grid md:grid-cols-2 gap-16 items-center">

    {/* LEFT SIDE */}
    <div>

      {/* Badge */}
      <div className="inline-block mb-6 px-4 py-2 rounded-full bg-cyan-500/10 border border-cyan-500/30 text-cyan-400 text-sm">
        Built for Real Estate Developers & Brokers
      </div>

      {/* Heading */}
      <h1 className="text-4xl md:text-6xl font-bold leading-tight text-white">
        Accelerate Real Estate Sales 
        <span className="block text-cyan-400 mt-2">
          With AI-Driven Lead Qualification 
        </span>
      </h1>

      {/* Subheading */}
      <p className="mt-6 text-lg text-gray-400 max-w-xl">
        SalesSetu instantly calls, qualifies, and nurtures every incoming property lead and reduce unqualified property leads by 60%.   
        Your sales team only speaks to serious buyers.
      </p>

      {/* CTA Buttons */}
      <div className="mt-10 flex gap-4 flex-wrap">
        <a
          href="#demo"
          className="bg-cyan-500 hover:bg-cyan-600 text-black font-semibold px-8 py-4 rounded-lg transition shadow-lg shadow-cyan-500/20"
        >
          Book Free Demo
        </a>

        <a
          href="#how-it-works"
          className="border border-gray-700 hover:border-gray-500 text-white px-8 py-4 rounded-lg transition"
        >
          See How It Works
        </a>
      </div>

      {/* Trust Line */}
      <p className="mt-8 text-sm text-gray-500">
        Works with Meta Ads, Google Ads, WhatsApp & Landing Pages.
      </p>
    </div>

    {/* RIGHT SIDE – Premium Card */}
    <div className="relative">
      <div className="bg-[#111111] border border-gray-800 rounded-2xl p-8 shadow-2xl">

        <h3 className="text-white text-lg font-medium mb-6">
          AI Qualification Flow
        </h3>

        <div className="space-y-4 text-sm text-gray-400">

          <div className="flex justify-between">
            <span>Lead Captured</span>
            <span className="text-green-400">✓</span>
          </div>

          <div className="flex justify-between">
            <span>Instant AI Call</span>
            <span className="text-green-400">✓</span>
          </div>

          <div className="flex justify-between">
            <span>Budget Verified</span>
            <span className="text-green-400">✓</span>
          </div>

          <div className="flex justify-between">
            <span>Site Visit Interested</span>
            <span className="text-cyan-400 font-medium">
              Hot Lead
            </span>
          </div>

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
<section id="how-it-works" className="bg-[#0F0F0F] py-24 px-6">
  <div className="max-w-6xl mx-auto text-center">

    {/* Section Header */}
    <h2 className="text-3xl md:text-4xl font-bold text-white">
      How Real Estate Lead Automation Works
    </h2>

    <p className="mt-4 text-gray-400 max-w-2xl mx-auto">
      From ad click to site visit — fully automated in seconds.
    </p>

    {/* Steps */}
    <div className="mt-16 grid md:grid-cols-3 gap-10 text-left">

      {/* Step 1 */}
      <div className="bg-[#151515] border border-gray-800 p-8 rounded-xl hover:border-cyan-500/40 transition">
        <div className="text-cyan-400 text-sm font-medium mb-3">
          Step 01
        </div>

        <h3 className="text-white text-xl font-semibold mb-4">
          Capture Every Lead
        </h3>

        <p className="text-gray-400 text-sm leading-relaxed">
          Leads from Meta Ads, Google Ads, WhatsApp, or landing pages
          are automatically stored and processed instantly.
        </p>
      </div>

      {/* Step 2 */}
      <div className="bg-[#151515] border border-gray-800 p-8 rounded-xl hover:border-cyan-500/40 transition">
        <div className="text-cyan-400 text-sm font-medium mb-3">
          Step 02
        </div>

        <h3 className="text-white text-xl font-semibold mb-4">
          AI Qualification Call
        </h3>

        <p className="text-gray-400 text-sm leading-relaxed">
          Our AI instantly calls the lead, verifies budget,
          timeline, location preference, and site visit interest.
        </p>
      </div>

      {/* Step 3 */}
      <div className="bg-[#151515] border border-gray-800 p-8 rounded-xl hover:border-cyan-500/40 transition">
        <div className="text-cyan-400 text-sm font-medium mb-3">
          Step 03
        </div>

        <h3 className="text-white text-xl font-semibold mb-4">
          Only Hot Leads to Sales Team
        </h3>

        <p className="text-gray-400 text-sm leading-relaxed">
          Your sales team receives only serious buyers,
          saving time and increasing conversion rates.
        </p>
      </div>

    </div>
  </div>
</section>

<section className="bg-[#0A0A0A] py-28 px-6 border-t border-gray-800">
  <div className="max-w-6xl mx-auto">

    {/* Section Heading */}
    <div className="text-center mb-20">
      <h2 className="text-3xl md:text-4xl font-bold text-white">
        AI Lead Qualification for Real Estate Developers & Brokers
      </h2>

      <p className="mt-4 text-gray-400 max-w-2xl mx-auto">
        Whether you're launching a new project or managing multiple inventories,
        SalesSetu ensures no serious buyer slips away.
      </p>
    </div>

    {/* Grid */}
    <div className="grid md:grid-cols-3 gap-12">

      {/* Developers */}
      <div className="bg-[#111111] border border-gray-800 rounded-2xl p-10 hover:border-cyan-500/40 transition">
        <h3 className="text-white text-xl font-semibold mb-6">
          For Developers
        </h3>

        <ul className="space-y-4 text-sm text-gray-400">
          <li>✔ Automatically qualify project inquiries</li>
          <li>✔ Reduce unproductive site visits</li>
          <li>✔ Increase sales team efficiency</li>
          <li>✔ Track campaign performance instantly</li>
        </ul>
      </div>

      {/* Channel Partners */}
      <div className="bg-[#111111] border border-gray-800 rounded-2xl p-10 hover:border-cyan-500/40 transition">
        <h3 className="text-white text-xl font-semibold mb-6">
          For Channel Partners
        </h3>

        <ul className="space-y-4 text-sm text-gray-400">
          <li>✔ Filter genuine buyers automatically</li>
          <li>✔ Follow up 24/7 without manual calling</li>
          <li>✔ Improve lead-to-visit conversion</li>
          <li>✔ Close faster with qualified prospects</li>
        </ul>
      </div>

      {/* Brokers */}
      <div className="bg-[#111111] border border-gray-800 rounded-2xl p-10 hover:border-cyan-500/40 transition">
        <h3 className="text-white text-xl font-semibold mb-6">
          For Brokers
        </h3>

        <ul className="space-y-4 text-sm text-gray-400">
          <li>✔ Save time on non-serious leads</li>
          <li>✔ Prioritize hot buyers instantly</li>
          <li>✔ Automate WhatsApp nurturing</li>
          <li>✔ Focus only on closing deals</li>
        </ul>
      </div>

    </div>

  </div>
</section>

<section className="bg-[#0F0F0F] py-28 px-6 border-t border-gray-800">
  <div className="max-w-6xl mx-auto text-center">

    {/* Header */}
    <h2 className="text-3xl md:text-4xl font-bold text-white">
      Real Estate AI Call Bot Workflow - From Ad Click to Site Visit 
    </h2>

    <p className="mt-4 text-gray-400 max-w-2xl mx-auto">
      SalesSetu automates the entire real estate lead journey in seconds.
    </p>

    {/* Flow Container */}
    <div className="mt-20 flex flex-col md:flex-row items-center justify-between gap-10 relative">

      {/* Step */}
      <div className="flow-step">
        <div className="flow-circle">Ads</div>
        <p className="flow-label">Meta / Google</p>
      </div>

      <div className="flow-line hidden md:block" />

      <div className="flow-step">
        <div className="flow-circle">Lead</div>
        <p className="flow-label">Captured Instantly</p>
      </div>

      <div className="flow-line hidden md:block" />

      <div className="flow-step">
        <div className="flow-circle">AI Call</div>
        <p className="flow-label">Budget & Intent</p>
      </div>

      <div className="flow-line hidden md:block" />

      <div className="flow-step">
        <div className="flow-circle">Hot Lead</div>
        <p className="flow-label">Verified Buyer</p>
      </div>

      <div className="flow-line hidden md:block" />

      <div className="flow-step">
        <div className="flow-circle">Visit</div>
        <p className="flow-label">Sales Team</p>
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
      SalesSetu is built to increase response time, lower cost per qualified lead, higher site visit rate, shorter closing cycle 
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

<section className="bg-[#0A0A0A] py-28 px-6 border-t border-gray-800">
  <div className="max-w-4xl mx-auto text-center">

    <h2 className="text-3xl md:text-4xl font-bold text-white mb-8">
      Real Estate Sales Acceleration, Not Just Lead Generation
    </h2>

    <p className="text-gray-400 leading-relaxed text-sm space-y-6">
      Most real estate businesses focus only on generating more leads.
      But the real problem is speed, qualification, and follow-up consistency.
      SalesSetu accelerates the entire sales cycle by instantly engaging,
      verifying, and prioritizing serious buyers.
    </p>

    <p className="text-gray-400 leading-relaxed text-sm mt-6">
      Instead of increasing ad spend, developers and brokers can improve
      site visit conversion, reduce wasted sales time, and shorten deal
      cycles through intelligent automation.
    </p>

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

<section className="bg-[#0A0A0A] py-28 px-6 border-t border-gray-800">
  <div className="max-w-4xl mx-auto">

    <h2 className="text-3xl md:text-4xl font-bold text-white mb-8 text-center">
      Why Real Estate Teams Lose 60% of Property Leads Without Automation
    </h2>

    <div className="space-y-6 text-gray-400 text-sm leading-relaxed">

      <p>
        Most real estate developers and brokers struggle with unqualified
        property leads. Manual follow-ups delay response time, and serious
        buyers often move to competitors within minutes.
      </p>

      <p>
        Real estate lead automation solves this problem by instantly calling,
        qualifying, and filtering prospects based on budget, timeline, and
        site visit interest.
      </p>

      <p>
        An AI call bot for real estate ensures that every incoming lead
        from Meta Ads, Google Ads, or landing pages is contacted within
        seconds — increasing conversion rates and reducing sales team workload.
      </p>

      <p>
        SalesSetu acts as a real estate automation platform that connects
        ads, CRM, WhatsApp, and AI voice qualification into one seamless system.
      </p>

    </div>

  </div>
</section>

<section className="bg-[#0F0F0F] py-28 px-6 border-t border-gray-800">
  <div className="max-w-4xl mx-auto">

    <h2 className="text-3xl md:text-4xl font-bold text-white text-center mb-16">
      Frequently Asked Questions About Real Estate Lead Automation
    </h2>

    <div className="space-y-8">

      {/* FAQ 1 */}
      <div className="border border-gray-800 rounded-xl p-6 bg-[#111111]">
        <h3 className="text-white font-semibold mb-3">
          What is real estate lead automation?
        </h3>
        <p className="text-gray-400 text-sm leading-relaxed">
          Real estate lead automation is a system that instantly captures,
          calls, and qualifies property inquiries from Meta Ads, Google Ads,
          or landing pages. It reduces response time and filters serious buyers automatically.
        </p>
      </div>

      {/* FAQ 2 */}
      <div className="border border-gray-800 rounded-xl p-6 bg-[#111111]">
        <h3 className="text-white font-semibold mb-3">
          How does the AI call bot work for property leads?
        </h3>
        <p className="text-gray-400 text-sm leading-relaxed">
          SalesSetu’s AI call bot contacts the lead within seconds,
          verifies budget, location preference, and site visit interest,
          and passes only qualified buyers to your sales team.
        </p>
      </div>

      {/* FAQ 3 */}
      <div className="border border-gray-800 rounded-xl p-6 bg-[#111111]">
        <h3 className="text-white font-semibold mb-3">
          Does SalesSetu integrate with Meta Ads and Google Ads?
        </h3>
        <p className="text-gray-400 text-sm leading-relaxed">
          Yes. SalesSetu captures leads from Meta Lead Ads,
          Google Ads landing pages, WhatsApp campaigns,
          and integrates them into a unified automation flow.
        </p>
      </div>

      {/* FAQ 4 */}
      <div className="border border-gray-800 rounded-xl p-6 bg-[#111111]">
        <h3 className="text-white font-semibold mb-3">
          Can it handle multiple real estate projects?
        </h3>
        <p className="text-gray-400 text-sm leading-relaxed">
          Yes. SalesSetu supports multi-project workflows,
          allowing developers and brokers to manage different inventories
          while tracking performance separately.
        </p>
      </div>

      {/* FAQ 5 */}
      <div className="border border-gray-800 rounded-xl p-6 bg-[#111111]">
        <h3 className="text-white font-semibold mb-3">
          Is this suitable for small brokers or only large developers?
        </h3>
        <p className="text-gray-400 text-sm leading-relaxed">
          SalesSetu is designed for both independent brokers and
          large-scale developers who want to improve lead quality,
          reduce manual follow-up, and increase site visit conversions.
        </p>
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
  href="https://wa.me/917060213244?text=Hi%20I%20want%20to%20know%20more%20about%20SalesSetu"
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
  </>
);
}           