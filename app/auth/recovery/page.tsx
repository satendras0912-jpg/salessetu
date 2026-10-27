import type { Metadata } from "next";
import Link from "next/link";
import { redirect } from "next/navigation";
import { confirmPasswordRecovery } from "./actions";
import { RECOVERY_ERROR_PATH, validRecoveryHash } from "@/lib/auth/recovery-routing";

export const dynamic = "force-dynamic";
export const metadata: Metadata = { title: "Confirm password reset | SalesSetu", robots: { index: false, follow: false }, referrer: "no-referrer" };

export default async function RecoveryPage({ searchParams }: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const tokenHash = params.token_hash;
  if (params.error || params.error_code || !validRecoveryHash(tokenHash)) redirect(RECOVERY_ERROR_PATH);
  return <main className="flex min-h-screen items-center justify-center bg-slate-950 px-4 py-12 text-white">
    <section className="w-full max-w-md rounded-3xl border border-slate-800 bg-slate-900 p-8">
      <p className="text-sm font-semibold uppercase tracking-widest text-cyan-400">SalesSetu</p>
      <h1 className="mt-4 text-3xl font-bold">Reset your password</h1>
      <p className="my-6 text-slate-400">Continue to verify your reset link and choose a new password.</p>
      <form action={confirmPasswordRecovery}>
        <input type="hidden" name="token_hash" value={tokenHash} />
        <button type="submit" className="w-full rounded-xl bg-cyan-500 px-5 py-3 font-semibold text-slate-950">Continue to reset password</button>
      </form>
      <Link href="/forgot-password" className="mt-6 block text-center text-sm text-cyan-300">Request a new reset link</Link>
    </section>
  </main>;
}
