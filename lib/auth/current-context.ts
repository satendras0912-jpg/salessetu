import { cache } from "react";

import { createClient } from "@/lib/supabase/server";

export type CurrentOrganization = {
  id: string;
  name: string;
  slug: string | null;
  status: string | null;
};

export type CurrentRole = {
  id: string;
  code: string;
  name: string;
};

export type CurrentMembership = {
  id: string;
  organizationId: string;
  membershipStatus: string | null;
  isOwner: boolean;
};

export type CurrentUserContext = {
  user: {
    id: string;
    email: string | null;
  };
  organization: CurrentOrganization | null;
  membership: CurrentMembership | null;
  roles: CurrentRole[];
};

async function loadCurrentUserContext(): Promise<CurrentUserContext | null> {
  const supabase = await createClient();

  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    return null;
  }

  const { data: memberships, error: membershipError } = await supabase
    .from("organization_members")
    .select(
      `
        id,
        organization_id,
        membership_status,
        is_owner
      `,
    )
    .eq("user_id", user.id)
    .eq("membership_status", "active")
    .limit(1);

  if (membershipError) {
    throw new Error(
      `Failed to load organization membership: ${membershipError.message}`,
    );
  }

  const membershipRecord = memberships?.[0];

  if (!membershipRecord) {
    return {
      user: {
        id: user.id,
        email: user.email ?? null,
      },
      organization: null,
      membership: null,
      roles: [],
    };
  }

  const { data: organization, error: organizationError } = await supabase
    .from("organizations")
    .select(
      `
        id,
        name,
        slug,
        status
      `,
    )
    .eq("id", membershipRecord.organization_id)
    .maybeSingle();

  if (organizationError) {
    throw new Error(
      `Failed to load organization: ${organizationError.message}`,
    );
  }

  const { data: assignedRoles, error: assignedRolesError } = await supabase
    .from("member_roles")
    .select("role_id")
    .eq("organization_member_id", membershipRecord.id);

  if (assignedRolesError) {
    throw new Error(
      `Failed to load assigned roles: ${assignedRolesError.message}`,
    );
  }

  const roleIds = [
    ...new Set(
      (assignedRoles ?? [])
        .map((assignment) => assignment.role_id)
        .filter((roleId): roleId is string => Boolean(roleId)),
    ),
  ];

  let roles: CurrentRole[] = [];

  if (roleIds.length > 0) {
    const { data: roleRecords, error: rolesError } = await supabase
      .from("roles")
      .select("id, code, name")
      .in("id", roleIds)
      .order("code");

    if (rolesError) {
      throw new Error(`Failed to load roles: ${rolesError.message}`);
    }

    roles = (roleRecords ?? []).map((role) => ({
      id: role.id,
      code: role.code,
      name: role.name,
    }));
  }

  return {
    user: {
      id: user.id,
      email: user.email ?? null,
    },

    organization: organization
      ? {
          id: organization.id,
          name: organization.name,
          slug: organization.slug,
          status: organization.status,
        }
      : null,

    membership: {
      id: membershipRecord.id,
      organizationId: membershipRecord.organization_id,
      membershipStatus: membershipRecord.membership_status,
      isOwner: Boolean(membershipRecord.is_owner),
    },

    roles,
  };
}

export const getCurrentUserContext = cache(loadCurrentUserContext);