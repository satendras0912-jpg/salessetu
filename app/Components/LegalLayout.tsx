export default function LegalLayout({
  title,
  children,
}: {
  title: string
  children: React.ReactNode
}) {
  return (
    <main className="min-h-screen bg-[#0B0F19] text-white px-6 py-24">
      <div className="max-w-5xl mx-auto">

        {/* Heading */}
        <div className="mb-16 text-center">
          <h1 className="text-5xl font-bold tracking-tight bg-gradient-to-r from-cyan-400 to-blue-500 bg-clip-text text-transparent">
            {title}
          </h1>
          <div className="w-24 h-1 bg-cyan-500 mx-auto mt-6 rounded-full"></div>
        </div>

        {/* Content Card */}
        <div className="bg-white/5 border border-white/10 backdrop-blur-xl rounded-2xl p-10 space-y-10 shadow-2xl">
          {children}
        </div>

      </div>
    </main>
  )
}