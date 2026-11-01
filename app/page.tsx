import { localeFrom, one, readQuery } from "./hr-query.ts";
import { HrChrome } from "./hr-chrome.tsx";

export default async function Home({
  searchParams,
}: {
  searchParams?: Promise<Record<string, string | string[] | undefined>> | Record<string, string | string[] | undefined>;
}) {
  const query = await readQuery(searchParams);
  const locale = localeFrom(one(query.lang));
  const people = locale === "fr-CA" ? "/people?lang=fr-CA" : "/people";
  const copy =
    locale === "fr-CA"
      ? {
          title: "CanDoHR",
          body: "La liste des personnes et les postes sont des exemples. La connexion et la base de données ne sont pas branchées.",
          link: "Personnes",
        }
      : {
          title: "CanDoHR",
          body: "The people list and the positions are sample records. Sign-in and the database are not connected yet.",
          link: "People",
        };
  return (
    <HrChrome locale={locale} path="/">
      <main className="mx-auto flex max-w-3xl flex-col gap-4 px-6 py-16">
        <p className="text-sm font-semibold uppercase tracking-wide text-orange-600">CanDoHR</p>
        <h1 className="text-4xl font-semibold leading-tight">{copy.title}</h1>
        <p className="text-lg leading-8 text-slate-700">{copy.body}</p>
        <a className="text-orange-700" href={people}>
          {copy.link}
        </a>
        <a className="text-orange-700" href={locale === "fr-CA" ? "/org-chart?lang=fr-CA" : "/org-chart"}>
          {locale === "fr-CA" ? "Organigramme" : "Org chart"}
        </a>
      </main>
    </HrChrome>
  );
}
