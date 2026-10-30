import { switchWorkspace } from "@/app/dashboard/workspace-actions";
import type { AvailableOrganization } from "@/lib/auth/current-context";

type WorkspaceSwitcherProps = {
  activeOrganizationId: string | null;
  organizations: readonly AvailableOrganization[];
};

export default function WorkspaceSwitcher({
  activeOrganizationId,
  organizations,
}: WorkspaceSwitcherProps) {
  if (organizations.length < 2) {
    return null;
  }

  return (
    <form action={switchWorkspace} className="flex items-center gap-2">
      <label className="sr-only" htmlFor="workspace-switcher">
        Switch workspace
      </label>

      <select
        id="workspace-switcher"
        name="organizationId"
        defaultValue={activeOrganizationId ?? ""}
        className="max-w-52 rounded-xl border border-slate-700 bg-slate-900 px-3 py-2 text-sm font-medium text-slate-100 outline-none transition focus:border-cyan-400"
      >
        {organizations.map((organization) => (
          <option key={organization.id} value={organization.id}>
            {organization.name}
            {organization.isOwner ? " (Owner)" : ""}
          </option>
        ))}
      </select>

      <button
        type="submit"
        className="rounded-xl border border-cyan-500/60 bg-cyan-500/10 px-3 py-2 text-sm font-semibold text-cyan-200 transition hover:bg-cyan-500/20"
      >
        Switch
      </button>
    </form>
  );
}
