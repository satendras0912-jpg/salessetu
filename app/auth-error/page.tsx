import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Authentication Error | SalesSetu",
};

type AuthErrorPageProps = {
  searchParams: Promise<{
    reason?: string;
  }>;
};

const errorMessages: Record<string, string> = {
  "missing-fields": "Email और password दोनों भरना आवश्यक है।",
  "invalid-login":
    "Email या password सही नहीं है, अथवा इस account को login की अनुमति नहीं है।",
  "logout-failed":
    "Session logout नहीं हो सका। कृपया दोबारा प्रयास करें।",
};

export default async function AuthErrorPage({
  searchParams,
}: AuthErrorPageProps) {
  const { reason } = await searchParams;

  const message =
    errorMessages[reason ?? ""] ??
    "Authentication request पूरी नहीं हो सकी। कृपया दोबारा प्रयास करें।";

  return (
    <main className="flex min-h-screen items-center justify-center bg-slate-950 px-4 text-white">
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

        <Link
          href="/login"
          className="mt-7 inline-flex rounded-xl bg-cyan-500 px-6 py-3 font-semibold text-slate-950 transition hover:bg-cyan-400"
        >
          Return to login
        </Link>
      </section>
    </main>
  );
}