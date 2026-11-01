import TeamManagementClient, {
  type ManagedSalesAgent,
} from "@/components/team/TeamManagementClient";
import {
  requirePermissionAccess,
} from "@/lib/auth/access-control";
import {
  createClient,
} from "@/lib/supabase/server";

export default async function TeamManagementPage() {
  const { context } = await requirePermissionAccess({
    allOf: ["organization.manage_members"],
    loginRedirectTo: "/login?next=/dashboard/team",
    unauthorizedRedirectTo: "/unauthorized",
  });

  const organizationId = context.organization?.id;

  if (!organizationId) {
    return null;
  }

  const supabase = await createClient();
  const { data, error } = await supabase.rpc(
    "list_organization_sales_agents",
    {
      p_organization_id: organizationId,
    },
  );

  if (error) {
    throw new Error(
      "Sales agents could not be loaded for this workspace.",
    );
  }

  const agents = Array.isArray(data)
    ? (data as ManagedSalesAgent[])
    : [];

  return (
    <TeamManagementClient
      organizationName={
        context.organization?.name ?? "This workspace"
      }
      agents={agents}
    />
  );
}
