import "server-only";

import {
  createClient as createSupabaseClient,
} from "@supabase/supabase-js";

function getAdminSupabaseConfig() {
  const url =
    process.env.NEXT_PUBLIC_SUPABASE_URL;

  const secretKey =
    process.env.SUPABASE_SECRET_KEY ??
    process.env.SUPABASE_SERVICE_ROLE_KEY;

  const publicKey =
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_URL is missing.",
    );
  }

  if (!secretKey) {
    throw new Error(
      "SUPABASE_SECRET_KEY or SUPABASE_SERVICE_ROLE_KEY is missing.",
    );
  }

  if (
    publicKey &&
    secretKey === publicKey
  ) {
    throw new Error(
      "The Supabase admin client cannot use a public key.",
    );
  }

  return {
    url,
    secretKey,
  };
}

export function createAdminClient() {
  const {
    url,
    secretKey,
  } = getAdminSupabaseConfig();

  return createSupabaseClient(
    url,
    secretKey,
    {
      auth: {
        autoRefreshToken: false,
        detectSessionInUrl: false,
        persistSession: false,
      },
    },
  );
}