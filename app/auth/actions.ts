"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";

import { createClient } from "@/lib/supabase/server";

function getApplicationUrl() {
  const configuredUrl =
    process.env.NEXT_PUBLIC_APP_URL?.trim();

  if (configuredUrl) {
    return configuredUrl.replace(/\/+$/, "");
  }

  const productionUrl =
    process.env.VERCEL_PROJECT_PRODUCTION_URL?.trim();

  if (productionUrl) {
    return `https://${productionUrl
      .replace(/^https?:\/\//, "")
      .replace(/\/+$/, "")}`;
  }

  const deploymentUrl =
    process.env.VERCEL_URL?.trim();

  if (deploymentUrl) {
    return `https://${deploymentUrl
      .replace(/^https?:\/\//, "")
      .replace(/\/+$/, "")}`;
  }

  return "http://localhost:3000";
}

export async function login(formData: FormData) {
  const email = String(formData.get("email") ?? "")
    .trim()
    .toLowerCase();

  const password = String(
    formData.get("password") ?? "",
  );

  if (!email || !password) {
    redirect(
      "/auth-error?reason=missing-fields",
    );
  }

  const supabase = await createClient();

  const { error } =
    await supabase.auth.signInWithPassword({
      email,
      password,
    });

  if (error) {
    redirect(
      "/auth-error?reason=invalid-login",
    );
  }

  revalidatePath("/", "layout");
  redirect("/dashboard");
}

export async function requestPasswordReset(
  formData: FormData,
) {
  const email = String(formData.get("email") ?? "")
    .trim()
    .toLowerCase();

  if (!email) {
    redirect(
      "/forgot-password?error=missing-email",
    );
  }

  const supabase = await createClient();

  const redirectTo =
    `${getApplicationUrl()}` +
    "/auth/callback?next=/update-password";

  const { error } =
    await supabase.auth.resetPasswordForEmail(
      email,
      {
        redirectTo,
      },
    );

  if (error) {
    console.error(
      "Password reset request failed:",
      error.message,
    );

    redirect(
      "/forgot-password?error=request-failed",
    );
  }

  redirect("/forgot-password?status=sent");
}

export async function logout() {
  const supabase = await createClient();

  const { error } = await supabase.auth.signOut();

  if (error) {
    redirect(
      "/auth-error?reason=logout-failed",
    );
  }

  revalidatePath("/", "layout");
  redirect("/login");
}