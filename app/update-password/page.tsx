import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";

import UpdatePasswordForm from "@/components/auth/UpdatePasswordForm";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Update Password | SalesSetu",
  description:
    "Choose a new password for your SalesSetu account.",
  robots: {
    index: false,
    follow: false,
  },
};

export const dynamic = "force-dynamic";

export default async function UpdatePasswordPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect(
      "/auth-error?reason=recovery-session-missing",
    );
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-4 py-12 text-white">
      <section className="w-full max-w-md rounded-3xl border border-slate-800 bg-slate-900 p-8 shadow-2xl">
        <div className="mb-8 text-center">
          <p className="mb-3 text-sm font-semibold uppercase tracking-[0.25em] text-cyan-400">
            SalesSetu Enterprise
          </p>

          <h1 className="text-3xl font-bold tracking-tight">
            Choose a new password
          </h1>

          <p className="mt-3 text-sm leading-6 text-slate-400">
            Create a strong password for your SalesSetu
            account. You will sign in again after the
            password is updated.
          </p>
        </div>

        <UpdatePasswordForm />

        <div className="mt-6 text-center">
          <Link
            href="/forgot-password"
            className="text-sm font-medium text-cyan-300 transition hover:text-cyan-200"
          >
            Request another reset link
          </Link>
        </div>
      </section>
    </main>
  );
}