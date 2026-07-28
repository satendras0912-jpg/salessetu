"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

import { createClient } from "@/lib/supabase/client";

export default function LogoutButton() {
  const router = useRouter();

  const [isLoggingOut, setIsLoggingOut] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  async function handleLogout() {
    if (isLoggingOut) {
      return;
    }

    setIsLoggingOut(true);
    setErrorMessage(null);

    const supabase = createClient();

    const { error } = await supabase.auth.signOut();

    if (error) {
      setErrorMessage(error.message);
      setIsLoggingOut(false);
      return;
    }

    router.replace("/login");
    router.refresh();
  }

  return (
    <div className="flex flex-col items-end gap-2">
      <button
        type="button"
        onClick={handleLogout}
        disabled={isLoggingOut}
        className="rounded-xl border border-red-900/70 bg-red-950/30 px-4 py-2 text-sm font-semibold text-red-300 transition hover:border-red-700 hover:bg-red-950/60 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isLoggingOut ? "Signing out..." : "Logout"}
      </button>

      {errorMessage ? (
        <p className="max-w-64 text-right text-xs text-red-400">
          {errorMessage}
        </p>
      ) : null}
    </div>
  );
}