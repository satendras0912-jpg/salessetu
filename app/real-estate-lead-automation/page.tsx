import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Real Estate Lead Automation Software | AI for Property Developers",
  description:
    "AI-powered real estate lead automation software that captures, calls, qualifies, and routes property leads automatically to improve site visit conversions.",
  keywords: [
    "real estate lead automation",
    "automate real estate leads",
    "property lead automation software",
    "real estate lead management automation",
    "AI lead automation for builders",
    "real estate follow up automation",
  ],
};

export default function RealEstateLeadAutomationPage() {
  return (
    <main className="bg-[#0A0A0A] text-white px-6 py-24">
      <div className="max-w-4xl mx-auto space-y-10">

        <h1 className="text-4xl md:text-5xl font-bold leading-tight">
          AI-Powered Real Estate Lead Automation Software for Developers & Brokers
        </h1>

        <p className="text-gray-400 leading-relaxed">
          Real estate lead automation is no longer optional for property developers and brokers.
          In a competitive housing market, response time and lead qualification determine
          whether a prospect becomes a site visit or disappears to a competitor.
        </p>

        <p className="text-gray-400 leading-relaxed">
          Modern real estate lead automation software captures inquiries from Meta Ads,
          Google Ads, landing pages, and WhatsApp campaigns — then instantly engages
          those leads using AI-powered calling and structured follow-up automation.
        </p>

        {/* SECTION 1 */}

        <h2 className="text-2xl font-semibold">
          What Is Real Estate Lead Automation?
        </h2>

        <p className="text-gray-400 leading-relaxed">
          Real estate lead automation refers to systems that automatically capture,
          contact, qualify, nurture, and route property inquiries without relying on
          manual sales coordination. Instead of waiting for a sales executive to call,
          AI systems respond within seconds.
        </p>

        <p className="text-gray-400 leading-relaxed">
          This automation ensures that every inquiry receives immediate attention,
          reducing lead leakage and improving overall site visit conversion rates.
          It transforms a scattered manual process into a structured sales engine.
        </p>

        {/* SECTION 2 */}

        <h2 className="text-2xl font-semibold">
          Why Real Estate Businesses Lose Valuable Leads
        </h2>

        <p className="text-gray-400 leading-relaxed">
          Most property businesses generate leads effectively but fail in the
          follow-up stage. Delayed response time dramatically reduces conversion probability.
          Buyers exploring multiple projects often book visits with whoever calls first.
        </p>

        <ul className="space-y-3 text-gray-400 list-disc pl-6">
          <li>Slow response time after inquiry submission</li>
          <li>Manual lead distribution delays</li>
          <li>Unqualified or fake inquiries</li>
          <li>Sales team overload</li>
          <li>High cost per qualified lead</li>
        </ul>

        <p className="text-gray-400 leading-relaxed">
          Real estate lead management automation eliminates these inefficiencies
          by building structured qualification pipelines.
        </p>

        {/* SECTION 3 */}

        <h2 className="text-2xl font-semibold">
          How AI-Powered Real Estate Lead Automation Works
        </h2>

        <ol className="space-y-4 text-gray-400 list-decimal pl-6">
          <li>
            Automatic lead capture from Meta Ads, Google Ads, landing pages,
            and website forms.
          </li>
          <li>
            Instant AI call engagement within seconds of inquiry submission.
          </li>
          <li>
            Budget, location, and intent qualification through conversational AI.
          </li>
          <li>
            Automated WhatsApp nurturing for follow-ups and reminders.
          </li>
          <li>
            Hot lead routing to human sales executives.
          </li>
        </ol>

        <p className="text-gray-400 leading-relaxed">
          This structured automation increases response speed and improves
          marketing ROI without increasing advertising spend.
        </p>

        {/* SECTION 4 */}

        <h2 className="text-2xl font-semibold">
          Manual Follow-Up vs Automated Lead Qualification
        </h2>

        <div className="grid md:grid-cols-2 gap-6 text-sm text-gray-400">
          <div className="border border-gray-800 p-6 rounded-lg bg-[#111111]">
            <h3 className="text-white font-semibold mb-3">Manual Process</h3>
            <ul className="space-y-2 list-disc pl-4">
              <li>Delayed engagement</li>
              <li>Inconsistent qualification</li>
              <li>High workload</li>
              <li>Lower site visit rate</li>
            </ul>
          </div>

          <div className="border border-gray-800 p-6 rounded-lg bg-[#111111]">
            <h3 className="text-white font-semibold mb-3">Automated System</h3>
            <ul className="space-y-2 list-disc pl-4">
              <li>Instant AI response</li>
              <li>Intent-based filtering</li>
              <li>Reduced manual effort</li>
              <li>Higher qualified visit conversion</li>
            </ul>
          </div>
        </div>

        {/* SECTION 5 */}

        <h2 className="text-2xl font-semibold">
          Benefits of Real Estate Lead Automation Software
        </h2>

        <ul className="space-y-3 text-gray-400 list-disc pl-6">
          <li>Faster site visit scheduling</li>
          <li>Lower cost per qualified lead</li>
          <li>Improved sales productivity</li>
          <li>Higher campaign ROI</li>
          <li>Better tracking and reporting</li>
          <li>Shorter deal closing cycle</li>
        </ul>

        <p className="text-gray-400 leading-relaxed">
          By automating real estate leads, developers create predictable
          conversion systems instead of relying on reactive sales efforts.
        </p>

        {/* SECTION 6 */}

        <h2 className="text-2xl font-semibold">
          Who Needs Real Estate Lead Automation?
        </h2>

        <p className="text-gray-400 leading-relaxed">
          Real estate lead automation software is ideal for:
        </p>

        <ul className="space-y-3 text-gray-400 list-disc pl-6">
          <li>Builders launching new projects</li>
          <li>Channel partners managing multiple listings</li>
          <li>Real estate brokers handling high inquiry volume</li>
          <li>Marketing agencies running property ads</li>
        </ul>

        {/* CTA */}

        <div className="text-center mt-14">
          <Link 
            href="/#demo"
            className="bg-cyan-500 hover:bg-cyan-600 text-black font-medium px-8 py-4 rounded-lg transition"
          >
            Book a Free Real Estate Automation Demo
          </Link>
        </div>

        {/* FAQ */}

        <h2 className="text-2xl font-semibold mt-16">
          Frequently Asked Questions
        </h2>

        <div className="space-y-6 text-gray-400 text-sm">
          <p>
            Real estate lead automation improves response speed and ensures only
            serious buyers reach your sales team.
          </p>
          <p>
            AI calling systems engage property inquiries instantly and reduce
            manual follow-up workload.
          </p>
          <p>
            Automated WhatsApp nurturing keeps prospects engaged until they
            schedule a site visit.
          </p>
        </div>

      </div>
    </main>
  );
}