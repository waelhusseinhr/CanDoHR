import { CanDoError } from "@candohr/shared";

export const LOCALES = ["en-CA", "fr-CA"] as const;
export type Locale = (typeof LOCALES)[number];

const MESSAGES = {
  "en-CA": {
    "chart.title": "Org chart",
    "chart.sample": "These are sample boxes. The database is not connected yet.",
    "chart.empty": "Nothing to show on this date.",
    "chart.move": "Move to…",
    "chart.asOf": "As of",
    "chart.compare": "Compare",
    "chart.hierarchy": "Hierarchy",
    "chart.vacant": "Vacant",
    "chart.filled": "Filled",
    "chart.today": "Today",
    "chart.manager": "Manager",
    "lang.switch": "Français",
  },
  "fr-CA": {
    "chart.title": "Organigramme",
    "chart.sample": "Ce sont des exemples. La base de données n'est pas branchée.",
    "chart.empty": "Rien à afficher à cette date.",
    "chart.move": "Déplacer vers…",
    "chart.asOf": "En date du",
    "chart.compare": "Comparer",
    "chart.hierarchy": "Hiérarchie",
    "chart.vacant": "Vacant",
    "chart.filled": "Comblé",
    "chart.today": "Aujourd'hui",
    "chart.manager": "Gestionnaire",
    "lang.switch": "English",
  },
} as const;

export type ChartMessageKey = keyof (typeof MESSAGES)["en-CA"];

export function chartMessageKeys(): ChartMessageKey[] {
  return Object.keys(MESSAGES["en-CA"]) as ChartMessageKey[];
}

export function ct(locale: Locale, key: ChartMessageKey): string {
  const text = MESSAGES[locale][key];
  if (!text) throw new CanDoError("INTERFACE_LANGUAGE_NOT_AVAILABLE");
  return text;
}

export function assertChartLocales(): void {
  const english = Object.keys(MESSAGES["en-CA"]).sort().join("\n");
  const french = Object.keys(MESSAGES["fr-CA"]).sort().join("\n");
  if (english !== french) throw new CanDoError("INTERFACE_LANGUAGE_NOT_AVAILABLE");
}
