"use client";

import { useEffect, useState, useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";

import { markNotificationReadAction } from "@/app/dashboard/notification-actions";

export type DashboardNotification = {
  id: string;
  title: string;
  body: string;
  deepLink: string | null;
  severity: "info" | "success" | "warning" | "error" | "critical";
  status: "unread" | "read" | "dismissed" | "archived";
  createdAt: string;
};

type NotificationInboxProps = {
  items: readonly DashboardNotification[];
};

function severityClassName(
  severity: DashboardNotification["severity"],
): string {
  if (severity === "critical" || severity === "error") {
    return "border-rose-500/40 bg-rose-500/10";
  }

  if (severity === "warning") {
    return "border-amber-500/40 bg-amber-500/10";
  }

  if (severity === "success") {
    return "border-emerald-500/40 bg-emerald-500/10";
  }

  return "border-cyan-500/40 bg-cyan-500/10";
}

function relativeTime(createdAt: string): string {
  const minutes = Math.max(
    0,
    Math.floor((Date.now() - new Date(createdAt).getTime()) / 60_000),
  );

  if (minutes < 1) {
    return "Just now";
  }

  if (minutes < 60) {
    return `${minutes}m ago`;
  }

  const hours = Math.floor(minutes / 60);

  if (hours < 24) {
    return `${hours}h ago`;
  }

  return new Intl.DateTimeFormat("en-IN", {
    day: "numeric",
    month: "short",
    timeZone: "Asia/Kolkata",
  }).format(new Date(createdAt));
}

export default function NotificationInbox({
  items,
}: NotificationInboxProps) {
  const router = useRouter();
  const [isOpen, setIsOpen] = useState(false);
  const [isPending, startTransition] = useTransition();
  const unreadCount = items.filter(
    (item) => item.status === "unread",
  ).length;

  useEffect(() => {
    const refresh = () => {
      if (document.visibilityState === "visible") {
        router.refresh();
      }
    };

    const intervalId = window.setInterval(refresh, 10_000);

    return () => window.clearInterval(intervalId);
  }, [router]);

  const openNotification = (item: DashboardNotification) => {
    startTransition(async () => {
      if (item.status === "unread") {
        await markNotificationReadAction(item.id);
      }

      setIsOpen(false);
      router.refresh();

      if (
        item.deepLink &&
        item.deepLink.startsWith("/dashboard/")
      ) {
        router.push(item.deepLink);
      }
    });
  };

  return (
    <div className="relative">
      <button
        type="button"
        aria-label={
          unreadCount > 0
            ? `Open alerts, ${unreadCount} unread`
            : "Open alerts"
        }
        aria-expanded={isOpen}
        onClick={() => setIsOpen((current) => !current)}
        className="relative rounded-xl border border-slate-700 px-3 py-2 text-sm font-semibold text-slate-100 transition hover:border-cyan-400 hover:text-cyan-200"
      >
        Alerts

        {unreadCount > 0 ? (
          <span className="ml-2 inline-flex min-w-5 items-center justify-center rounded-full bg-cyan-400 px-1.5 py-0.5 text-xs font-bold text-slate-950">
            {unreadCount > 99 ? "99+" : unreadCount}
          </span>
        ) : null}
      </button>

      {isOpen ? (
        <section
          aria-label="Notification inbox"
          className="absolute right-0 z-50 mt-3 w-[min(24rem,calc(100vw-2rem))] overflow-hidden rounded-2xl border border-slate-700 bg-slate-950 shadow-2xl shadow-black/50"
        >
          <div className="flex items-center justify-between border-b border-slate-800 px-4 py-3">
            <div>
              <p className="font-semibold text-white">
                Alerts
              </p>
              <p className="text-xs text-slate-400">
                Refreshes every 10 seconds
              </p>
            </div>

            {isPending ? (
              <span className="text-xs text-cyan-300">
                Updating…
              </span>
            ) : null}
          </div>

          {items.length > 0 ? (
            <ul className="max-h-96 divide-y divide-slate-800 overflow-y-auto">
              {items.map((item) => (
                <li key={item.id}>
                  <button
                    type="button"
                    onClick={() => openNotification(item)}
                    className={[
                      "w-full px-4 py-3 text-left transition hover:bg-slate-900",
                      item.status === "unread"
                        ? "bg-slate-900/70"
                        : "",
                    ].join(" ")}
                  >
                    <div className="flex gap-3">
                      <span
                        aria-hidden="true"
                        className={[
                          "mt-1 h-2.5 w-2.5 shrink-0 rounded-full border",
                          severityClassName(item.severity),
                        ].join(" ")}
                      />

                      <span className="min-w-0">
                        <span className="flex items-center justify-between gap-3">
                          <span className="truncate font-medium text-white">
                            {item.title}
                          </span>

                          <span className="shrink-0 text-xs text-slate-500">
                            {relativeTime(item.createdAt)}
                          </span>
                        </span>

                        <span className="mt-1 block text-sm text-slate-300">
                          {item.body}
                        </span>
                      </span>
                    </div>
                  </button>
                </li>
              ))}
            </ul>
          ) : (
            <div className="px-4 py-8 text-center">
              <p className="font-medium text-slate-200">
                No alerts yet
              </p>
              <p className="mt-1 text-sm text-slate-500">
                Assigned leads and due follow-ups appear here.
              </p>
            </div>
          )}

          <div className="border-t border-slate-800 px-4 py-3">
            <Link
              href="/dashboard/follow-ups"
              onClick={() => setIsOpen(false)}
              className="text-sm font-semibold text-cyan-300 hover:text-cyan-200"
            >
              Open follow-up worklist
            </Link>
          </div>
        </section>
      ) : null}
    </div>
  );
}
