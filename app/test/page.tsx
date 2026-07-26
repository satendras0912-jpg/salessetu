import { createClient } from "@/lib/supabase/client";

export default function TestPage() {
  createClient();

  return (
    <main style={{ padding: "40px" }}>
      <h1>SalesSetu Enterprise</h1>
      <p>Supabase client initialized successfully.</p>
    </main>
  );
}