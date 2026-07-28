import { logout } from "@/app/auth/actions";

export default function LogoutButton() {
  return (
    <form action={logout}>
      <button
        type="submit"
        className="rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-2 text-sm font-semibold text-red-300 transition hover:border-red-400 hover:bg-red-500/20 hover:text-red-200"
      >
        Logout
      </button>
    </form>
  );
}