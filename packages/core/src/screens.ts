import { createElement as h, type ReactNode } from "react";
import { ct, type Locale } from "./i18n.ts";
import type { PersonListItem, PositionView, ProfileTab, ProfileView } from "./views.ts";

export { ct, type Locale } from "./i18n.ts";
export type { PersonListItem, PositionView, ProfileTab, ProfileView } from "./views.ts";

const shell = "mx-auto flex max-w-3xl flex-col gap-4 px-6 py-10";

function withLang(path: string, locale: Locale): string {
  if (locale !== "fr-CA") return path;
  const [base, query] = path.split("?");
  // structural: optional value absent; empty string for typing
  const params = new URLSearchParams(query ?? "");
  params.set("lang", "fr-CA");
  return `${base}?${params.toString()}`;
}

const TABS: ProfileTab[] = ["overview", "job", "pay", "leave", "documents", "history"];

export function PeopleList(props: { locale: Locale; people: readonly PersonListItem[]; sample?: boolean }): ReactNode {
  const { locale, people, sample } = props;
  return h(
    "main",
    { "data-screen": "people", className: shell },
    h("h1", { className: "text-3xl font-semibold" }, ct(locale, "people.title")),
    sample ? h("p", { className: "text-slate-600" }, ct(locale, "people.sample")) : null,
    people.length === 0
      ? h("p", null, ct(locale, "people.empty"))
      : h(
          "ul",
          { className: "divide-y divide-slate-200 rounded-lg border border-slate-200 bg-white" },
          people.map((person) =>
            h(
              "li",
              { key: person.id, className: "px-4 py-3" },
              h("a", { href: withLang(`/people/${person.id}`, locale), className: "font-medium text-orange-700" }, person.preferredName),
              person.title ? h("span", null, ` · ${person.title}`) : null,
              person.orgUnitName ? h("span", null, ` · ${person.orgUnitName}`) : null,
            ),
          ),
        ),
  );
}

export function PositionList(props: { locale: Locale; positions: readonly PositionView[]; sample?: boolean }): ReactNode {
  const { locale, positions, sample } = props;
  return h(
    "main",
    { "data-screen": "positions", className: shell },
    h("h1", { className: "text-3xl font-semibold" }, ct(locale, "positions.title")),
    sample ? h("p", { className: "text-slate-600" }, ct(locale, "people.sample")) : null,
    positions.length === 0
      ? h("p", null, ct(locale, "positions.empty"))
      : h(
          "ul",
          { className: "divide-y divide-slate-200 rounded-lg border border-slate-200 bg-white" },
          positions.map((position) =>
            h(
              "li",
              { key: position.id, className: "px-4 py-3" },
              h("a", { href: withLang(`/positions/${position.id}`, locale), className: "font-medium text-orange-700" }, position.title),
              h("span", null, ` · ${ct(locale, position.status === "filled" ? "position.filled" : "position.vacant")}`),
              position.holderName ? h("span", null, ` · ${position.holderName}`) : null,
            ),
          ),
        ),
  );
}

export function PersonProfile(props: { locale: Locale; profile: ProfileView | null; tab?: ProfileTab }): ReactNode {
  const { locale } = props;
  if (!props.profile) return h("main", { "data-screen": "profile", className: shell }, h("p", null, ct(locale, "profile.missing")));
  const profile = props.profile;
  // structural: nullish coalescing for optional input in tests or adapters
  const tab = props.tab ?? "overview";
  return h(
    "main",
    { "data-screen": "profile", className: shell },
    h("h1", { className: "text-3xl font-semibold" }, profile.preferredName),
    h(
      "nav",
      { "aria-label": ct(locale, "profile.title"), className: "flex flex-wrap gap-3 text-sm" },
      TABS.map((item) =>
        h(
          "a",
          {
            key: item,
            href: withLang(`?tab=${item}`, locale),
            "aria-current": item === tab ? "page" : undefined,
            className: item === tab ? "font-semibold text-orange-700" : "text-slate-600",
          },
          ct(locale, tabKey(item)),
        ),
      ),
    ),
    tab === "overview"
      ? h(
          "section",
          null,
          h("p", null, `${ct(locale, "field.legal")}: ${profile.legalName}`),
          h("p", null, `${ct(locale, "field.preferred")}: ${profile.preferredName}`),
          profile.sinMasked ? h("p", null, profile.sinMasked) : null,
        )
      : null,
    tab === "job"
      ? h(
          "section",
          null,
          profile.assignments.map((row) =>
            h(
              "article",
              { key: row.id },
              h("p", null, `${ct(locale, "field.status")}: ${row.status}`),
              h("p", null, `${ct(locale, "field.primary")}: ${row.primary ? ct(locale, "field.yes") : ct(locale, "field.no")}`),
              h("p", null, `${ct(locale, "field.manager")}: ${row.managerName ?? ""}`), // structural: optional display field
              // structural: optional value absent; empty string for typing
              h("p", null, `${ct(locale, "field.agreement")}: ${row.agreementId ?? ""}`),
              h("p", null, `${ct(locale, "field.rate")}: ${row.rate}`),
            ),
          ),
        )
      : null,
    tab === "pay"
      // structural: optional value absent; empty string for typing
      ? h("section", null, h("p", null, `${ct(locale, "field.tax")}: ${profile.taxProvince ?? ""}`))
      : null,
    tab === "leave" ? h("section", null, ct(locale, "tab.leave")) : null,
    tab === "documents" ? h("section", null, ct(locale, "tab.documents")) : null,
    tab === "history"
      ? h(
          "section",
          null,
          h(
            "ol",
            null,
            profile.history.map((row) => h("li", { key: `${row.date}-${row.label}` }, `${row.date} ${row.label}`)),
          ),
        )
      : null,
  );
}

export function PositionScreen(props: { locale: Locale; position: PositionView | null }): ReactNode {
  const { locale } = props;
  if (!props.position) return h("main", { "data-screen": "position", className: shell }, h("p", null, ct(locale, "position.missing")));
  const position = props.position;
  return h(
    "main",
    { "data-screen": "position", className: shell },
    h("h1", { className: "text-3xl font-semibold" }, position.title),
    h("p", null, `${ct(locale, "field.status")}: ${ct(locale, position.status === "filled" ? "position.filled" : "position.vacant")}`),
    h("p", null, `${ct(locale, "field.fte")}: ${position.fteBudget}`),
    h("p", null, position.orgUnitName),
    position.holderName ? h("p", null, position.holderName) : null,
  );
}

function tabKey(tab: ProfileTab): "tab.overview" | "tab.job" | "tab.pay" | "tab.leave" | "tab.documents" | "tab.history" {
  if (tab === "overview") return "tab.overview";
  if (tab === "job") return "tab.job";
  if (tab === "pay") return "tab.pay";
  if (tab === "leave") return "tab.leave";
  if (tab === "documents") return "tab.documents";
  return "tab.history";
}
