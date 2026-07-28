import type { Metadata } from "next";
import { redirect } from "next/navigation";

import { login } from "@/app/auth/actions";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Login | SalesSetu",
  description: "Secure login for the SalesSetu enterprise platform.",
};

export const dynamic = "force-dynamic";

export default async function LoginPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (user) {
    redirect("/dashboard");
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-4 py-12 text-white">
      <section className="w-full max-w-md rounded-3xl border border-slate-800 bg-slate-900 p-8 shadow-2xl">
        <div className="mb-8 text-center">
          <p className="mb-3 text-sm font-semibold uppercase tracking-[0.25em] text-cyan-400">
            SalesSetu Enterprise
          </p>

          <h1 className="text-3xl font-bold tracking-tight">
            Welcome back
          </h1>

          <p className="mt-3 text-sm leading-6 text-slate-400">
            अपने SalesSetu workspace में securely login करें।
          </p>
        </div>

        <form action={login} className="space-y-5">
          <div>
            <label
              htmlFor="email"
              className="mb-2 block text-sm font-medium text-slate-200"
            >
              Email address
            </label>

            <input
              id="email"
              name="email"
              type="email"
              autoComplete="email"
              required
              placeholder="admin@salessetu.in"
              className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-white outline-none transition placeholder:text-slate-600 focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20"
            />
          </div>

          <div>
            <label
              htmlFor="password"
              className="mb-2 block text-sm font-medium text-slate-200"
            >
              Password
            </label>

            <input
              id="password"
              name="password"
              type="password"
              autoComplete="current-password"
              required
              placeholder="Enter your password"
              className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-white outline-none transition placeholder:text-slate-600 focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20"
            />
          </div>

          <button
            type="submit"
            className="w-full rounded-xl bg-cyan-500 px-5 py-3 font-semibold text-slate-950 transition hover:bg-cyan-400 focus:outline-none focus:ring-2 focus:ring-cyan-400 focus:ring-offset-2 focus:ring-offset-slate-900"
          >
            Sign in
          </button>
        </form>

        <div className="mt-6 rounded-xl border border-slate-800 bg-slate-950/60 p-4">
          <p className="text-center text-xs leading-5 text-slate-500">
            Access is restricted to authorised SalesSetu users. Public
            registration is disabled.
          </p>
        </div>
      </section>
    </main>
  );
}