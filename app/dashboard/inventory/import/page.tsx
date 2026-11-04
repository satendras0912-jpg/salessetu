import Link from "next/link";

import InventoryImportWizard from "@/components/inventory/InventoryImportWizard";
import { requirePermissionAccess } from "@/lib/auth/access-control";

export const dynamic = "force-dynamic";

export default async function InventoryImportPage() {
  const { context } = await requirePermissionAccess({
    allOf: [
      "inventory.view",
      "inventory.create",
    ],
    loginRedirectTo: "/login?next=/dashboard/inventory/import",
    unauthorizedRedirectTo: "/unauthorized",
  });

  return (
    <div className="space-y-8">
      <header className="flex flex-col justify-between gap-6 xl:flex-row xl:items-end">
        <div>
          <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
            PropertyOS
          </p>
          <h1 className="mt-3 text-4xl font-bold tracking-tight text-white">
            Safe Inventory Import
          </h1>
          <p className="mt-3 max-w-3xl text-base leading-7 text-slate-400">
            Verified commercial inventory ko CSV se preview, validate aur
            controlled batch mein add karein. Import existing units ko update
            ya overwrite nahi karta.
          </p>
        </div>

        <div className="flex flex-wrap gap-3">
          <Link
            href="/dashboard/inventory"
            className="rounded-xl border border-slate-700 px-4 py-3 text-sm font-semibold text-slate-300 transition hover:border-cyan-500 hover:text-cyan-300"
          >
            ← Back to inventory
          </Link>
          <span className="rounded-xl border border-slate-800 bg-slate-900 px-4 py-3 text-sm text-slate-400">
            {context.organization?.name ?? "Active workspace"}
          </span>
        </div>
      </header>

      <section className="grid gap-4 md:grid-cols-3">
        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="font-semibold text-white">1. Validate locally</p>
          <p className="mt-2 text-sm leading-6 text-slate-400">
            Required headers, in-file duplicate codes and controlled values are
            checked before anything leaves your browser.
          </p>
        </article>
        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="font-semibold text-white">2. Verify on server</p>
          <p className="mt-2 text-sm leading-6 text-slate-400">
            Project ownership and existing unit conflicts are checked again in
            the active organization before saving.
          </p>
        </article>
        <article className="rounded-2xl border border-slate-800 bg-slate-900/70 p-5">
          <p className="font-semibold text-white">3. Preserve audit trail</p>
          <p className="mt-2 text-sm leading-6 text-slate-400">
            Every imported unit stores source, verification date and publication
            status. Existing records remain unchanged.
          </p>
        </article>
      </section>

      <InventoryImportWizard />
    </div>
  );
}
