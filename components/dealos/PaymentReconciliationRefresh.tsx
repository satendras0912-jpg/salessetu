"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";

export default function PaymentReconciliationRefresh() {
  const router = useRouter();

  useEffect(() => {
    const timer = window.setInterval(() => {
      if (document.visibilityState === "visible") router.refresh();
    }, 30_000);

    return () => window.clearInterval(timer);
  }, [router]);

  return <p className="text-sm text-emerald-300">Live reconciliation is on · refreshes every 30 seconds</p>;
}
