"use server";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { RECOVERY_ERROR_PATH, validRecoveryHash } from "@/lib/auth/recovery-routing";

export async function confirmPasswordRecovery(formData: FormData) {
  const tokenHash = formData.get("token_hash");
  if (!validRecoveryHash(tokenHash)) redirect(RECOVERY_ERROR_PATH);
  // Verify only on an explicit form POST, not on email scanner/prefetch GET requests.
  const supabase = await createClient();
  let verified = false;
  try {
    const { data, error } = await supabase.auth.verifyOtp({ token_hash: tokenHash, type: "recovery" });
    verified = !error && Boolean(data.user && data.session);
  } catch {
    verified = false;
  }
  if (!verified) redirect(RECOVERY_ERROR_PATH);
  redirect("/update-password");
}
