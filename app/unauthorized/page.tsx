import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Access Denied | SalesSetu",
  description:
    "Your account does not have permission to access this SalesSetu workspace.",
};

export default function UnauthorizedPage() {
  return (
    <main className="min-h-screen bg-slate-950 px-6 py-16 text-white">
      <div className="mx-auto flex min-h-[70vh] max-w-3xl items-center justify-center">
        <section className="w-full rounded-3xl border border-red-950 bg-slate-900 p-8 shadow-2xl md:p-12">
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-red-400">
            SalesSetu Enterprise
          </p>

          <h1 className="mt-4 text-3xl font-bold md:text-4xl">
            Access denied
          </h1>

          <p className="mt-5 max-w-2xl leading-7 text-slate-300">
            Your account is authenticated, but it does not have the required
            organization membership or administrative role to access this
            workspace.
          </p>

          <div className="mt-8 rounded-2xl border border-slate-800 bg-slate-950 p-5">
            <p className="text-sm font-medium text-slate-300">
              Access requires:
            </p>

            <ul className="mt-3 space-y-2 text-sm text-slate-400">
              <li>• An active SalesSetu organization</li>
              <li>• An active organization membership</li>
              <li>• Owner access or the Platform Administrator role</li>
            </ul>
          </div>

          <div className="mt-8 flex flex-wrap gap-4">
            <Link
              href="/"
              className="rounded-xl bg-cyan-400 px-5 py-3 font-semibold text-slate-950 transition hover:bg-cyan-300"
            >
              Return to homepage
            </Link>

            <Link
              href="/login"
              className="rounded-xl border border-slate-700 px-5 py-3 font-semibold text-slate-200 transition hover:border-slate-500 hover:bg-slate-800"
            >
              Sign in with another account
            </Link>
          </div>
        </section>
      </div>
    </main>
  );
}