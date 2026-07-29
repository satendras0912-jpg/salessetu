function Skeleton({
  className,
}: {
  className: string;
}) {
  return (
    <div
      className={`animate-pulse rounded-xl bg-slate-800 ${className}`}
    />
  );
}

export default function LeadOperationsLoading() {
  return (
    <div className="space-y-8">
      <div>
        <Skeleton className="h-4 w-52" />
        <Skeleton className="mt-4 h-12 w-80 max-w-full" />
        <Skeleton className="mt-4 h-5 w-[620px] max-w-full" />
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        {Array.from({ length: 4 }).map((_, index) => (
          <div
            key={index}
            className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
          >
            <Skeleton className="h-4 w-28" />
            <Skeleton className="mt-4 h-9 w-20" />
          </div>
        ))}
      </div>

      <div className="rounded-3xl border border-slate-800 bg-slate-900 p-5">
        <Skeleton className="h-6 w-48" />

        <div className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-6">
          {Array.from({ length: 6 }).map((_, index) => (
            <Skeleton key={index} className="h-12 w-full" />
          ))}
        </div>
      </div>

      <div className="overflow-hidden rounded-3xl border border-slate-800 bg-slate-900">
        {Array.from({ length: 7 }).map((_, index) => (
          <div
            key={index}
            className="grid grid-cols-4 gap-5 border-b border-slate-800 p-5 last:border-b-0"
          >
            <Skeleton className="h-12 w-full" />
            <Skeleton className="h-12 w-full" />
            <Skeleton className="h-12 w-full" />
            <Skeleton className="h-12 w-full" />
          </div>
        ))}
      </div>
    </div>
  );
}