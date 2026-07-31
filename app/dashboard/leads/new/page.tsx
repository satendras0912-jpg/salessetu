import { redirect } from "next/navigation";

import LeadForm from "@/components/leads/LeadForm";

import { createLeadAction } from "@/app/dashboard/leads/actions";

import { requirePermissionAccess } from "@/lib/auth/access-control";

import {
  DEFAULT_LEAD_FORM_VALUES,
  LEAD_FORM_PERMISSIONS,
} from "@/lib/leads/lead-form-contract";

import {
  getLeadSources,
} from "@/lib/leads/lead-service";

export const dynamic = "force-dynamic";

export default async function NewLeadPage() {
  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_FORM_PERMISSIONS.view,
        LEAD_FORM_PERMISSIONS.create,
      ],

      loginRedirectTo:
        "/login?next=/dashboard/leads/new",

      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organizationId =
    context.organization?.id;

  if (!organizationId) {
    redirect(
      "/auth-error?reason=organization_context_missing",
    );
  }

  const sources = await getLeadSources(
    organizationId,
  );

  return (
    <div className="space-y-8">
      <header>
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
          Lead Operations
        </p>

        <h1 className="mt-3 text-4xl font-bold tracking-tight text-white">
          Create Lead
        </h1>

        <p className="mt-3 max-w-3xl text-base leading-7 text-slate-400">
          Manually add a customer enquiry to the
          current SalesSetu organization.
        </p>
      </header>

      <LeadForm
        mode="create"
        action={createLeadAction}
        initialValues={DEFAULT_LEAD_FORM_VALUES}
        sources={sources}
        cancelHref="/dashboard/leads"
      />
    </div>
  );
}