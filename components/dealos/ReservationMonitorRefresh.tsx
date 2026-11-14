"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

type ReservationMonitorRefreshProps = {
  organizationId: string;
};

export default function ReservationMonitorRefresh({
  organizationId,
}: ReservationMonitorRefreshProps) {
  const router = useRouter();

  useEffect(() => {
    const intervalId = window.setInterval(() => {
      if (document.visibilityState === "visible") {
        router.refresh();
      }
    }, 10_000);

    return () => window.clearInterval(intervalId);
  }, [organizationId, router]);

  return (
    <p
      aria-live="polite"
      className="text-xs font-medium text-emerald-300"
    >
      Live reservation monitoring is on · refreshes every 10 seconds
    </p>
  );
}
