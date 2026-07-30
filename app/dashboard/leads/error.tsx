"use client";

import { useEffect } from "react";

type LeadOperationsErrorProps = {
  error: Error & {
    digest?: string;
  };
  reset: () => void;
};

export default function LeadOperationsError({
  error,
  reset,
}: LeadOperationsErrorProps) {
  useEffect(() => {
    console.error("Lead Operations error:", error);
  }, [error]);

  return (
    <section className="rounded-3xl border border-red-900/70 bg-red-950/20 p-8">
      <p className="text-sm font-semibold uppercase tracking-[0.25em] text-red-400">
        Lead Operations
      </p>

      <h1 className="mt-3 text-3xl font-bold text-white">
        Leads could not be loaded
      </h1>

      <p className="mt-4 max-w-2xl text-sm leading-6 text-red-200/80">
        Database query, permission या organization context में
        समस्या आई है। Retry करने से पहले browser console और
        server terminal में error देखें।
      </p>

      <div className="mt-6 rounded-xl border border-red-900/60 bg-slate-950/70 p-4">
        <p className="break-words font-mono text-xs text-red-300">
          {error.message}
        </p>

        {error.digest ? (
          <p className="mt-2 font-mono text-xs text-slate-600">
            Digest: {error.digest}
          </p>
        ) : null}
      </div>

      <button
        type="button"
        onClick={reset}
        className="mt-6 rounded-xl bg-red-400 px-6 py-3 text-sm font-semibold text-slate-950 transition hover:bg-red-300"
      >
        Try again
      </button>
    </section>
  );
}