export default function Home() {
  return (
    <main className="min-h-screen bg-slate-50 px-6 py-16 text-slate-950">
      <section className="mx-auto flex max-w-2xl flex-col gap-4">
        <p className="text-sm font-semibold uppercase tracking-wide text-orange-600">CanDoHR</p>
        <h1 className="text-4xl font-semibold leading-tight">CanDoHR is running on this computer.</h1>
        <p className="text-lg leading-8 text-slate-700">
          This is the starting page. Sign-in, the database, and the public website at candohr.ca are
          not set up yet.
        </p>
      </section>
    </main>
  );
}
