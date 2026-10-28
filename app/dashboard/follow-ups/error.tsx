"use client";
export default function FollowUpError({ reset }: { reset: () => void }) {
  return <div className="rounded-2xl border border-rose-900 p-6" role="alert">
    <h2 className="text-xl font-semibold">Follow-ups could not be loaded</h2>
    <p className="mt-2 text-slate-400">Please try again. Your saved tasks have not been changed.</p>
    <button onClick={reset} className="mt-4 rounded-xl border border-slate-600 px-4 py-2">Try again</button>
  </div>;
}
