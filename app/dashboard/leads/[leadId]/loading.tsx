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

export default function LeadDetailLoading() {
  return (
    <div className="space-y-8">
      <div>
        <Skeleton className="h-4 w-44" />
        <Skeleton className="mt-6 h-12 w-80 max-w-full" />
        <Skeleton className="mt-4 h-8 w-72 max-w-full" />
      </div>

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-5">
        {Array.from({ length: 5 }).map(
          (_, index) => (
            <div
              key={index}
              className="rounded-2xl border border-slate-800 bg-slate-900 p-5"
            >
              <Skeleton className="h-4 w-24" />
              <Skeleton className="mt-4 h-8 w-16" />
            </div>
          ),
        )}
      </div>

      {Array.from({ length: 5 }).map(
        (_, sectionIndex) => (
          <div
            key={sectionIndex}
            className="rounded-3xl border border-slate-800 bg-slate-900 p-6"
          >
            <Skeleton className="h-7 w-52" />

            <div className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
              {Array.from({
                length: 4,
              }).map((_, itemIndex) => (
                <Skeleton
                  key={itemIndex}
                  className="h-24 w-full"
                />
              ))}
            </div>
          </div>
        ),
      )}
    </div>
  );
}