import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Authentication Error | SalesSetu",
  robots: {
    index: false,
    follow: false,
  },
};

type AuthErrorPageProps = {
  searchParams: Promise<{
    reason?: string;
  }>;
};

const errorMessages: Record<string, string> = {
  "missing-fields":
    "Email and password are both required.",
  "invalid-login":
    "The email or password is incorrect, or this account is not permitted to sign in.",
  "logout-failed":
    "The session could not be closed. Please try again.",
  "recovery-link-invalid":
    "This password-reset link is invalid, expired or has already been used. Request a new link.",
  "recovery-session-missing":
    "A valid password-recovery session was not found. Request a new reset link.",
};

export default async function AuthErrorPage({
  searchParams,
}: AuthErrorPageProps) {
  const { reason } = await searchParams;

  const message =
    errorMessages[reason ?? ""] ??
    "The authentication request could not be completed. Please try again.";

  const recoveryError =
    reason === "recovery-link-invalid" ||
    reason === "recovery-session-missing";

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-4 py-12 text-white">
      <section className="w-full max-w-lg rounded-3xl border border-red-500/20 bg-slate-900 p-8 text-center shadow-2xl">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-red-500/10 text-2xl text-red-300">
          !
        </div>

        <h1 className="mt-5 text-2xl font-bold">
          Authentication failed
        </h1>

        <p className="mt-4 leading-7 text-slate-400">
          {message}
        </p>

        <div className="mt-7 flex flex-col justify-center gap-3 sm:flex-row">
          {recoveryError ? (
            <Link
              href="/forgot-password"
              className="inline-flex justify-center rounded-xl bg-cyan-500 px-6 py-3 font-semibold text-slate-950 transition hover:bg-cyan-400"
            >
              Request a new reset link
            </Link>
          ) : null}

          <Link
            href="/login"
            className="inline-flex justify-center rounded-xl border border-slate-700 bg-slate-950 px-6 py-3 font-semibold text-slate-200 transition hover:border-slate-600 hover:bg-slate-800"
          >
            Return to login
          </Link>
        </div>
      </section>
    </main>
  );
}