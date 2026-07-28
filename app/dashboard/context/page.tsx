import { requirePermissionAccess } from "@/lib/auth/access-control";

export default async function DashboardContextPage() {
  const { context, permissions } =
    await requirePermissionAccess({
      allOf: [
        "dashboard.view",
        "dashboard.context.read",
      ],
      loginRedirectTo:
        "/login?next=/dashboard/context",
      unauthorizedRedirectTo:
        "/unauthorized",
    });

  const organization = context.organization;
  const membership = context.membership;

  const permissionCount =
    permissions.codes.length;

  return (
    <div className="space-y-8">
      <section>
        <p className="text-sm font-semibold uppercase tracking-[0.28em] text-cyan-400">
          SalesSetu Enterprise
        </p>

        <h1 className="mt-3 text-4xl font-bold text-white">
          Organization Context
        </h1>

        <p className="mt-3 max-w-3xl text-slate-400">
          Authenticated user, active organization,
          membership, roles and effective permissions.
        </p>
      </section>

      <section className="rounded-3xl border border-slate-800 bg-slate-900 p-7">
        <h2 className="text-2xl font-bold text-white">
          Authenticated User
        </h2>

        <div className="mt-6 grid gap-6 md:grid-cols-2">
          <ContextField
            label="User ID"
            value={context.user.id}
          />

          <ContextField
            label="Email"
            value={
              context.user.email ??
              "Email unavailable"
            }
          />
        </div>
      </section>

      <section className="rounded-3xl border border-slate-800 bg-slate-900 p-7">
        <h2 className="text-2xl font-bold text-white">
          Organization
        </h2>

        <div className="mt-6 grid gap-6 md:grid-cols-2">
          <ContextField
            label="Organization ID"
            value={
              organization?.id ??
              "Unavailable"
            }
          />

          <ContextField
            label="Name"
            value={
              organization?.name ??
              "Unavailable"
            }
          />

          <ContextField
            label="Slug"
            value={
              organization?.slug ??
              "Unavailable"
            }
          />

          <ContextField
            label="Status"
            value={
              organization?.status ??
              "Unavailable"
            }
          />
        </div>
      </section>

      <section className="rounded-3xl border border-slate-800 bg-slate-900 p-7">
        <h2 className="text-2xl font-bold text-white">
          Membership
        </h2>

        <div className="mt-6 grid gap-6 md:grid-cols-2">
          <ContextField
            label="Membership status"
            value={
              membership?.membershipStatus ??
              "Unavailable"
            }
          />

          <ContextField
            label="Organization owner"
            value={
              membership?.isOwner
                ? "Yes"
                : "No"
            }
          />
        </div>
      </section>

      <section className="rounded-3xl border border-slate-800 bg-slate-900 p-7">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <h2 className="text-2xl font-bold text-white">
              Assigned Roles
            </h2>

            <p className="mt-1 text-sm text-slate-400">
              Roles resolved for the active
              organization membership.
            </p>
          </div>

          <span className="rounded-full border border-cyan-800 bg-cyan-950/50 px-4 py-2 text-sm font-medium text-cyan-300">
            {context.roles.length} role
            {context.roles.length === 1
              ? ""
              : "s"}
          </span>
        </div>

        <div className="mt-6 grid gap-4 md:grid-cols-2">
          {context.roles.length > 0 ? (
            context.roles.map((role) => (
              <div
                key={role.id}
                className="rounded-2xl border border-slate-800 bg-slate-950 p-5"
              >
                <p className="font-semibold text-white">
                  {role.name}
                </p>

                <p className="mt-1 text-sm text-slate-500">
                  {role.code}
                </p>
              </div>
            ))
          ) : (
            <p className="text-slate-400">
              No assigned roles found.
            </p>
          )}
        </div>
      </section>

      <section className="rounded-3xl border border-slate-800 bg-slate-900 p-7">
        <div className="flex flex-wrap items-center justify-between gap-4">
          <div>
            <h2 className="text-2xl font-bold text-white">
              Effective Permissions
            </h2>

            <p className="mt-1 text-sm text-slate-400">
              Database-resolved permissions available
              in the current organization.
            </p>
          </div>

          <span className="rounded-full border border-emerald-800 bg-emerald-950/40 px-4 py-2 text-sm font-medium text-emerald-300">
            {permissionCount} permissions
          </span>
        </div>

        <div className="mt-6 grid gap-3 md:grid-cols-2 xl:grid-cols-3">
          {permissions.codes.map(
            (permissionCode) => (
              <div
                key={permissionCode}
                className="rounded-xl border border-slate-800 bg-slate-950 px-4 py-3 font-mono text-sm text-cyan-300"
              >
                {permissionCode}
              </div>
            ),
          )}
        </div>
      </section>
    </div>
  );
}

type ContextFieldProps = {
  label: string;
  value: string;
};

function ContextField({
  label,
  value,
}: ContextFieldProps) {
  return (
    <div className="rounded-2xl border border-slate-800 bg-slate-950 p-5">
      <p className="text-sm text-slate-500">
        {label}
      </p>

      <p className="mt-2 break-words font-medium text-slate-100">
        {value}
      </p>
    </div>
  );
}