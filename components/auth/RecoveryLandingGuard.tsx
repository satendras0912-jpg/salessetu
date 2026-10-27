"use client";
import { useEffect } from "react";
import { RECOVERY_ERROR_PATH } from "@/lib/auth/recovery-routing";

// URL fragments are invisible to the server. Never leave auth failures on the marketing page.
export default function RecoveryLandingGuard() {
  useEffect(() => {
    const params = new URLSearchParams(window.location.hash.slice(1));
    if (params.has("error") || params.has("error_code") || params.get("type") === "recovery") {
      window.history.replaceState(null, "", "/");
      window.location.replace(RECOVERY_ERROR_PATH);
    }
  }, []);
  return null;
}
