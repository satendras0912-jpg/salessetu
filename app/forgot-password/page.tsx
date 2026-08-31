import type { Metadata } from "next";
import Link from "next/link";

import { requestPasswordReset } from "@/app/auth/actions";

export const metadata: Metadata = {
  title: "Forgot Password | SalesSetu",
  description:
    "Request a secure SalesSetu password reset link.",
};

export const dynamic = "force-dynamic";

type ForgotPasswordPageProps = {
  searchParams: Promise<{
    status?: string;
    error?: string;
  }>;
};

const errorMessages: Record<string, string> = {
  "missing-email":
    "Enter the email address linked to your SalesSetu account.",
  "request-failed":
    "The reset request could not be completed. Please wait and try again.",
};

export default async function ForgotPasswordPage({
  searchParams,
}: ForgotPasswordPageProps) {
  const { status, error } = await searchParams;

  const errorMessage =
    errorMessages[error ?? ""] ?? null;

  const requestSent = status === "sent";

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-4 py-12 text-white">
      <section className="w-full max-w-md rounded-3xl border border-slate-800 bg-slate-900 p-8 shadow-2xl">
        <div className="mb-8 text-center">
          <p className="mb-3 text-sm font-semibold uppercase tracking-[0.25em] text-cyan-400">
            SalesSetu Enterprise
          </p>

          <h1 className="text-3xl font-bold tracking-tight">
            Reset your password
          </h1>

          <p className="mt-3 text-sm leading-6 text-slate-400">
            Enter your registered email address. We will
            send a secure password-reset link if the
            account exists.
          </p>
        </div>

        {requestSent ? (
          <div
            role="status"
            className="mb-6 rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-4 text-sm leading-6 text-emerald-200"
          >
            If an account exists for this email, a
            password-reset link has been sent. Check your
            inbox and spam folder.
          </div>
        ) : null}

        {errorMessage ? (
          <div
            role="alert"
            className="mb-6 rounded-xl border border-red-500/30 bg-red-500/10 p-4 text-sm leading-6 text-red-200"
          >
            {errorMessage}
          </div>
        ) : null}

        <form
          action={requestPasswordReset}
          className="space-y-5"
        >
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

          <button
            type="submit"
            className="w-full rounded-xl bg-cyan-500 px-5 py-3 font-semibold text-slate-950 transition hover:bg-cyan-400 focus:outline-none focus:ring-2 focus:ring-cyan-400 focus:ring-offset-2 focus:ring-offset-slate-900"
          >
            Send reset link
          </button>
        </form>

        <div className="mt-6 text-center">
          <Link
            href="/login"
            className="text-sm font-medium text-cyan-300 transition hover:text-cyan-200"
          >
            Return to sign in
          </Link>
        </div>
      </section>
    </main>
  );
}