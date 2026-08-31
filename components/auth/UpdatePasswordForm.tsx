"use client";

import type { FormEvent } from "react";
import { useState } from "react";

import { createClient } from "@/lib/supabase/client";

export default function UpdatePasswordForm() {
  const [errorMessage, setErrorMessage] =
    useState<string | null>(null);

  const [isSubmitting, setIsSubmitting] =
    useState(false);

  async function handleSubmit(
    event: FormEvent<HTMLFormElement>,
  ) {
    event.preventDefault();

    if (isSubmitting) {
      return;
    }

    setErrorMessage(null);

    const formData = new FormData(
      event.currentTarget,
    );

    const password = String(
      formData.get("password") ?? "",
    );

    const confirmPassword = String(
      formData.get("confirmPassword") ?? "",
    );

    if (password.length < 12) {
      setErrorMessage(
        "Use a password with at least 12 characters.",
      );
      return;
    }

    if (password !== confirmPassword) {
      setErrorMessage(
        "The password confirmation does not match.",
      );
      return;
    }

    setIsSubmitting(true);

    try {
      const supabase = createClient();

      const { error } =
        await supabase.auth.updateUser({
          password,
        });

      if (error) {
        console.error(
          "Password update failed:",
          error.message,
        );

        setErrorMessage(
          "The password could not be updated. Request a new reset link and try again.",
        );
        return;
      }

      await supabase.auth.signOut({
        scope: "global",
      });

      window.location.replace(
        "/login?status=password-updated",
      );
    } catch (error) {
      console.error(
        "Unexpected password update error:",
        error,
      );

      setErrorMessage(
        "An unexpected error occurred. Request a new reset link and try again.",
      );
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form
      onSubmit={handleSubmit}
      className="space-y-5"
    >
      {errorMessage ? (
        <div
          role="alert"
          className="rounded-xl border border-red-500/30 bg-red-500/10 p-4 text-sm leading-6 text-red-200"
        >
          {errorMessage}
        </div>
      ) : null}

      <div>
        <label
          htmlFor="password"
          className="mb-2 block text-sm font-medium text-slate-200"
        >
          New password
        </label>

        <input
          id="password"
          name="password"
          type="password"
          autoComplete="new-password"
          minLength={12}
          required
          placeholder="Enter a strong password"
          className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-white outline-none transition placeholder:text-slate-600 focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20"
        />

        <p className="mt-2 text-xs leading-5 text-slate-500">
          Use at least 12 characters. A mix of uppercase,
          lowercase, numbers and symbols is recommended.
        </p>
      </div>

      <div>
        <label
          htmlFor="confirmPassword"
          className="mb-2 block text-sm font-medium text-slate-200"
        >
          Confirm new password
        </label>

        <input
          id="confirmPassword"
          name="confirmPassword"
          type="password"
          autoComplete="new-password"
          minLength={12}
          required
          placeholder="Enter the password again"
          className="w-full rounded-xl border border-slate-700 bg-slate-950 px-4 py-3 text-white outline-none transition placeholder:text-slate-600 focus:border-cyan-500 focus:ring-2 focus:ring-cyan-500/20"
        />
      </div>

      <button
        type="submit"
        disabled={isSubmitting}
        className="w-full rounded-xl bg-cyan-500 px-5 py-3 font-semibold text-slate-950 transition hover:bg-cyan-400 focus:outline-none focus:ring-2 focus:ring-cyan-400 focus:ring-offset-2 focus:ring-offset-slate-900 disabled:cursor-not-allowed disabled:opacity-60"
      >
        {isSubmitting
          ? "Updating password..."
          : "Update password"}
      </button>
    </form>
  );
}