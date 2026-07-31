import {
  notFound,
  redirect,
} from "next/navigation";

import LeadForm from "@/components/leads/LeadForm";

import { updateLeadAction } from "@/app/dashboard/leads/actions";

import { requirePermissionAccess } from "@/lib/auth/access-control";

import {
  LEAD_FORM_PERMISSIONS,
} from "@/lib/leads/lead-form-contract";

import {
  getLeadEditContext,
} from "@/lib/leads/lead-edit-service";

import {
  getLeadSources,
} from "@/lib/leads/lead-service";

import type { LeadSourceSummary } from "@/types/leads";

export const dynamic = "force-dynamic";

type EditLeadPageProps = {
  params: Promise<{
    leadId: string;
  }>;
};

function mergeLeadSources(
  activeSources: LeadSourceSummary[],
  currentSource: LeadSourceSummary | null,
): LeadSourceSummary[] {
  if (
    !currentSource ||
    activeSources.some(
      (source) =>
        source.id === currentSource.id,
    )
  ) {
    return activeSources;
  }

  return [
    currentSource,
    ...activeSources,
  ];
}

export default async function EditLeadPage({
  params,
}: EditLeadPageProps) {
  const { leadId } = await params;

  const { context } =
    await requirePermissionAccess({
      allOf: [
        LEAD_FORM_PERMISSIONS.view,
        LEAD_FORM_PERMISSIONS.update,
      ],

      loginRedirectTo:
        `/login?next=/dashboard/leads/${leadId}/edit`,

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

  const [editContext, activeSources] =
    await Promise.all([
      getLeadEditContext(
        organizationId,
        leadId,
      ),

      getLeadSources(organizationId),
    ]);

  if (!editContext) {
    notFound();
  }

  const sources = mergeLeadSources(
    activeSources,
    editContext.currentSource,
  );

  return (
    <div className="space-y-8">
      <header>
        <p className="text-sm font-semibold uppercase tracking-[0.3em] text-cyan-400">
          Lead Operations
        </p>

        <h1 className="mt-3 text-4xl font-bold tracking-tight text-white">
          Edit Lead
        </h1>

        <p className="mt-3 max-w-3xl text-base leading-7 text-slate-400">
          Update contact, requirement, attribution
          and sales information for this lead.
        </p>
      </header>

      <LeadForm
        mode="edit"
        action={updateLeadAction}
        initialValues={editContext.values}
        sources={sources}
        cancelHref={`/dashboard/leads/${leadId}`}
      />
    </div>
  );
}