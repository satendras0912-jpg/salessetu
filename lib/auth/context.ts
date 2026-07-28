import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

export type SalesSetuProfile = {
  id: string;
  first_name: string | null;
  last_name: string | null;
  display_name: string | null;
  phone: string | null;
  status: string;
  timezone: string;
  locale: string;
};

export type SalesSetuOrganization = {
  id: string;
  name: string;
  slug: string;
  organization_type: string;
  status: string;
};

export type SalesSetuRole = {
  code: string;
  name: string;
};

type RelationValue<T> = T | T[] | null;

type MembershipRecord = {
  id: string;
  organization_id: string;
  membership_status: string;
  is_owner: boolean;
  joined_at: string | null;

  organization: RelationValue<SalesSetuOrganization>;

  role_assignments: Array<{
    role: RelationValue<SalesSetuRole>;
  }>;
};

function firstRelation<T>(
  value: RelationValue<T>,
): T | null {
  if (Array.isArray(value)) {
    return value[0] ?? null;
  }

  return value;
}

export async function getCurrentUserContext() {
  const supabase = await createClient();

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    redirect("/login");
  }

  const [
    profileResponse,
    membershipResponse,
  ] = await Promise.all([
    supabase
      .from("profiles")
      .select(
        `
          id,
          first_name,
          last_name,
          display_name,
          phone,
          status,
          timezone,
          locale
        `,
      )
      .eq("id", user.id)
      .maybeSingle(),

    supabase
      .from("organization_members")
      .select(
        `
          id,
          organization_id,
          membership_status,
          is_owner,
          joined_at,

          organization:organizations (
            id,
            name,
            slug,
            organization_type,
            status
          ),

          role_assignments:member_roles (
            role:roles (
              code,
              name
            )
          )
        `,
      )
      .eq("user_id", user.id)
      .eq("membership_status", "active")
      .order("created_at", {
        ascending: true,
      })
      .limit(1)
      .maybeSingle(),
  ]);

  if (profileResponse.error) {
    throw new Error(
      `Unable to load user profile: ${profileResponse.error.message}`,
    );
  }

  if (membershipResponse.error) {
    throw new Error(
      `Unable to load organization membership: ${membershipResponse.error.message}`,
    );
  }

  const profile =
    profileResponse.data as SalesSetuProfile | null;

  const membership =
    membershipResponse.data as unknown as MembershipRecord | null;

  if (!membership) {
    redirect("/access-denied?reason=no-membership");
  }

  const organization =
    firstRelation(membership.organization);

  if (!organization) {
    redirect("/access-denied?reason=no-organization");
  }

  if (
    profile?.status === "inactive" ||
    profile?.status === "suspended"
  ) {
    redirect("/access-denied?reason=inactive-profile");
  }

  if (organization.status !== "active") {
    redirect("/access-denied?reason=inactive-organization");
  }

  const roles = membership.role_assignments
    .map((assignment) =>
      firstRelation(assignment.role),
    )
    .filter(
      (role): role is SalesSetuRole =>
        role !== null,
    );

  const roleCodes = roles.map(
    (role) => role.code,
  );

  return {
    user,
    profile,
    membership,
    organization,
    roles,
    roleCodes,
  };
}

export async function hasOrganizationPermission(
  organizationId: string,
  permissionCode: string,
) {
  const supabase = await createClient();

  const {
    data,
    error,
  } = await supabase.rpc(
    "has_organization_permission",
    {
      requested_organization_id:
        organizationId,

      requested_permission_code:
        permissionCode,
    },
  );

  if (error) {
    throw new Error(
      `Permission check failed: ${error.message}`,
    );
  }

  return data === true;
}

export async function requireOrganizationPermission(
  permissionCode: string,
) {
  const context =
    await getCurrentUserContext();

  const allowed =
    context.membership.is_owner ||
    (await hasOrganizationPermission(
      context.organization.id,
      permissionCode,
    ));

  if (!allowed) {
    redirect(
      `/access-denied?reason=missing-permission&permission=${encodeURIComponent(
        permissionCode,
      )}`,
    );
  }

  return context;
}