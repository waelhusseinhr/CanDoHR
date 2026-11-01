import { ct, type Locale } from "@candohr/core/screens";
import type { ReactNode } from "react";

export function HrChrome(props: { locale: Locale; path: string; tab?: string; children: ReactNode }) {
  const { locale, path, tab, children } = props;
  const other: Locale = locale === "fr-CA" ? "en-CA" : "fr-CA";
  const home = locale === "fr-CA" ? "/?lang=fr-CA" : "/";
  const people = locale === "fr-CA" ? "/people?lang=fr-CA" : "/people";
  const positions = locale === "fr-CA" ? "/positions?lang=fr-CA" : "/positions";
  return (
    <div className="min-h-screen bg-slate-50 text-slate-950">
      <header className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex max-w-3xl items-center justify-between gap-4 px-6 py-4">
          <nav className="flex items-center gap-4 text-sm">
            <a className="font-semibold uppercase tracking-wide text-orange-600" href={home}>
              CanDoHR
            </a>
            <a href={people}>{ct(locale, "people.title")}</a>
            <a href={positions}>{ct(locale, "positions.title")}</a>
          </nav>
          <a className="text-sm text-orange-700" href={langHref(path, other, tab)}>
            {ct(locale, "lang.switch")}
          </a>
        </div>
      </header>
      {children}
    </div>
  );
}

function langHref(path: string, locale: Locale, tab?: string): string {
  const params = new URLSearchParams();
  if (locale === "fr-CA") params.set("lang", "fr-CA");
  if (tab && tab !== "overview") params.set("tab", tab);
  const query = params.toString();
  return query ? `${path}?${query}` : path;
}
