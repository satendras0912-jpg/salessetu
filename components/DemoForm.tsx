"use client";

import { useEffect, useState } from "react";
import type { FormEventHandler } from "react";

export default function DemoForm() {
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);
  const [error, setError] = useState("");
  const [utm, setUtm] = useState({
    source: "website",
    medium: "organic",
    campaign: "direct",
    term: "",
    content: "",
    landingPageUrl: "",
    referrerUrl: "",
  });

  // Capture UTM parameters
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);

    setUtm({
      source: params.get("utm_source")?.trim().toLowerCase() || "website",
      medium: params.get("utm_medium")?.trim().toLowerCase() || "organic",
      campaign: params.get("utm_campaign")?.trim() || "direct",
      term: params.get("utm_term")?.trim() || "",
      content: params.get("utm_content")?.trim() || "",
      landingPageUrl: window.location.href,
      referrerUrl: document.referrer || "",
    });
  }, []);

  const handleSubmit: FormEventHandler<HTMLFormElement> = async (e) => {
    e.preventDefault();

    const formElement = e.currentTarget;
    const formData = new FormData(formElement);
    setLoading(true);
    setError("");
    setSuccess(false);

    try {
      const payload = {
        name: formData.get("name"),
        phone: formData.get("phone"),
        project: formData.get("project"),
        location: formData.get("location"),
        source: utm.source,
        medium: utm.medium,
        campaign: utm.campaign,
        utm_source: utm.source,
        utm_medium: utm.medium,
        utm_campaign: utm.campaign,
        utm_term: utm.term || null,
        utm_content: utm.content || null,
        landing_page_url: utm.landingPageUrl,
        referrer_url: utm.referrerUrl || null,
        consent: formData.get("consent") === "on",
      };

      const response = await fetch("/api/lead-capture", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        throw new Error("Demo enquiry could not be delivered");
      }

      setSuccess(true);
      formElement.reset();
    } catch (err) {
      console.error("Error:", err);
      setError("Something went wrong. Please try again.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <form
      onSubmit={handleSubmit}
      className="bg-[#1a1a1a] p-8 rounded-2xl space-y-5 shadow-xl"
    >
      <input
        type="text"
        name="name"
        placeholder="Full Name"
        required
        className="w-full p-4 rounded-xl bg-white text-black"
      />

      <input
        type="tel"
        name="phone"
        placeholder="Phone Number"
        required
        className="w-full p-4 rounded-xl bg-white text-black"
      />

      <input
        type="text"
        name="project"
        placeholder="Project Name"
        required
        className="w-full p-4 rounded-xl bg-white text-black"
      />

      <input
        type="text"
        name="location"
        placeholder="Location"
        required
        className="w-full p-4 rounded-xl bg-white text-black"
      />

      <label className="flex items-start gap-3 text-sm leading-6 text-gray-300">
        <input
          type="checkbox"
          name="consent"
          required
          className="mt-1 h-4 w-4 rounded border-gray-600 accent-cyan-500"
        />
        <span>
          I agree to be contacted by SalesSetu via call, WhatsApp, SMS or
          AI-assisted communication about my demo enquiry. See the{" "}
          <a className="text-cyan-400 underline" href="/privacy-policy">
            Privacy Policy
          </a>
          .
        </span>
      </label>

      <button
        type="submit"
        disabled={loading}
        className="w-full bg-cyan-500 hover:bg-cyan-600 transition text-black font-semibold py-4 rounded-xl"
      >
        {loading ? "Submitting..." : "Schedule Demo"}
      </button>

      {success && (
        <p className="text-green-400 text-center">
          Demo booked successfully!
        </p>
      )}

      {error && (
        <p className="text-red-400 text-center">
          {error}
        </p>
      )}
    </form>
  );
}
