"use client";

import { useEffect, useState } from "react";

export default function DemoForm() {
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);
  const [error, setError] = useState("");
  const [utm, setUtm] = useState({
    source: "Website",
    medium: "Organic",
    campaign: "Direct",
  });

  // Capture UTM parameters
  useEffect(() => {
    const params = new URLSearchParams(window.location.search);

    setUtm({
      source: params.get("utm_source") || "Website",
      medium: params.get("utm_medium") || "Organic",
      campaign: params.get("utm_campaign") || "Direct",
    });
  }, []);

  const handleSubmit = async (e: any) => {
    e.preventDefault();
    setLoading(true);
    setError("");
    setSuccess(false);

    const formData = new FormData(e.target);

    try {
      const response = await fetch(
        "https://automation.salessetu.in/webhook/sales-lead",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            name: formData.get("name"),
            phone: formData.get("phone"),
            project: formData.get("project"),
            location: formData.get("location"),
            source: utm.source,
            medium: utm.medium,
            campaign: utm.campaign,
          }),
        }
      );

      if (!response.ok) {
        throw new Error("Webhook failed");
      }

      setSuccess(true);
      e.target.reset();
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