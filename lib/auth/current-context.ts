import { cache } from "react";
import { cookies } from "next/headers";

import { createClient } from "@/lib/supabase/server";

export const ACTIVE_ORGANIZATION_COOKIE =
  "salessetu_active_organization_id";

export const ACTIVE_ORGANIZATION_COOKIE_MAX_AGE =
  60 * 60 * 24 * 180;

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

export type AvailableOrganization = {
  id: string;
  name: string;
  slug: string | null;
  organizationType: string | null;
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
  availableOrganizations: AvailableOrganization[];
};

async function loadCurrentUserContext(): Promise<CurrentUserContext | null> {
  const supabase = await createClient();
  const cookieStore = await cookies();

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
        is_owner,
        created_at
      `,
    )
    .eq("user_id", user.id)
    .eq("membership_status", "active")
    .order("created_at", { ascending: true });

  if (membershipError) {
    throw new Error(
      `Failed to load organization membership: ${membershipError.message}`,
    );
  }

  const activeMemberships = memberships ?? [];
  const firstMembership = activeMemberships[0];

  if (!firstMembership) {
    return {
      user: {
        id: user.id,
        email: user.email ?? null,
      },
      organization: null,
      membership: null,
      roles: [],
      availableOrganizations: [],
    };
  }

  const organizationIds = [
    ...new Set(
      activeMemberships
        .map((membership) => membership.organization_id)
        .filter((organizationId): organizationId is string =>
          Boolean(organizationId),
        ),
    ),
  ];

  const { data: organizations, error: organizationsError } = await supabase
    .from("organizations")
    .select(
      `
        id,
        name,
        slug,
        status,
        organization_type
      `,
    )
    .in("id", organizationIds);

  if (organizationsError) {
    throw new Error(
      `Failed to load organizations: ${organizationsError.message}`,
    );
  }

  const organizationsById = new Map(
    (organizations ?? []).map((organization) => [
      organization.id,
      organization,
    ]),
  );

  const availableOrganizations = activeMemberships
    .map((membership) => {
      const organization = organizationsById.get(
        membership.organization_id,
      );

      if (!organization || organization.status !== "active") {
        return null;
      }

      return {
        id: organization.id,
        name: organization.name,
        slug: organization.slug,
        organizationType: organization.organization_type,
        isOwner: Boolean(membership.is_owner),
      } satisfies AvailableOrganization;
    })
    .filter(
      (
        organization,
      ): organization is AvailableOrganization =>
        organization !== null,
    );

  const requestedOrganizationId = cookieStore.get(
    ACTIVE_ORGANIZATION_COOKIE,
  )?.value;

  const selectedOrganization =
    availableOrganizations.find(
      (organization) => organization.id === requestedOrganizationId,
    ) ?? availableOrganizations[0];

  const membershipRecord = activeMemberships.find(
    (membership) =>
      membership.organization_id === selectedOrganization?.id,
  );

  if (!membershipRecord || !selectedOrganization) {
    return {
      user: {
        id: user.id,
        email: user.email ?? null,
      },
      organization: null,
      membership: null,
      roles: [],
      availableOrganizations,
    };
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

    organization: selectedOrganization
      ? {
          id: selectedOrganization.id,
          name: selectedOrganization.name,
          slug: selectedOrganization.slug,
          status: "active",
        }
      : null,

    membership: {
      id: membershipRecord.id,
      organizationId: membershipRecord.organization_id,
      membershipStatus: membershipRecord.membership_status,
      isOwner: Boolean(membershipRecord.is_owner),
    },

    roles,
    availableOrganizations,
  };
}

export const getCurrentUserContext = cache(loadCurrentUserContext);
