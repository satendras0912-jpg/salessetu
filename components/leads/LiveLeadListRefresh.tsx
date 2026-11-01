"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";

import { createClient } from "@/lib/supabase/client";

type LiveLeadListRefreshProps = {
  organizationId: string;
};

export default function LiveLeadListRefresh({
  organizationId,
}: LiveLeadListRefreshProps) {
  const router = useRouter();
  const refreshTimer = useRef<ReturnType<
    typeof setTimeout
  > | null>(null);

  useEffect(() => {
    const supabase = createClient();

    const scheduleRefresh = () => {
      if (refreshTimer.current) {
        return;
      }

      refreshTimer.current = setTimeout(() => {
        refreshTimer.current = null;
        router.refresh();
      }, 300);
    };

    const channel = supabase
      .channel(`lead-list:${organizationId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "leads",
          filter: `organization_id=eq.${organizationId}`,
        },
        scheduleRefresh,
      )
      .subscribe();

    return () => {
      if (refreshTimer.current) {
        clearTimeout(refreshTimer.current);
      }

      void supabase.removeChannel(channel);
    };
  }, [organizationId, router]);

  return (
    <p
      aria-live="polite"
      className="text-xs font-medium text-emerald-300"
    >
      Live lead updates are on
    </p>
  );
}
