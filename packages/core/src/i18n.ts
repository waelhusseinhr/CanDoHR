import { CanDoError } from "@candohr/shared";

export const LOCALES = ["en-CA", "fr-CA"] as const;
export type Locale = (typeof LOCALES)[number];

const MESSAGES = {
  "en-CA": {
    "people.title": "People",
    "people.empty": "No people to show.",
    "people.sample": "These are sample records. The database is not connected yet.",
    "profile.title": "Person",
    "profile.missing": "That person is not in the sample records.",
    "tab.overview": "Overview",
    "tab.job": "Job and assignments",
    "tab.pay": "Pay and payroll profile",
    "tab.leave": "Leave",
    "tab.documents": "Documents",
    "tab.history": "History",
    "position.title": "Position",
    "position.missing": "That position is not in the sample records.",
    "position.vacant": "Vacant",
    "position.filled": "Filled",
    "field.preferred": "Preferred name",
    "field.legal": "Legal name",
    "field.tax": "Tax province",
    "field.primary": "Primary",
    "field.rate": "Rate",
    "field.agreement": "Agreement",
    "field.manager": "Manager",
    "field.status": "Status",
    "field.fte": "FTE",
    "field.yes": "Yes",
    "field.no": "No",
    "positions.title": "Positions",
    "positions.empty": "No positions to show.",
    "lang.switch": "Français",
    "nav.skip": "Skip to content",
  },
  "fr-CA": {
    "people.title": "Personnes",
    "people.empty": "Aucune personne à afficher.",
    "people.sample": "Ce sont des exemples. La base de données n'est pas branchée.",
    "profile.title": "Personne",
    "profile.missing": "Cette personne n'est pas dans les exemples.",
    "tab.overview": "Aperçu",
    "tab.job": "Poste et affectations",
    "tab.pay": "Paie et profil de paie",
    "tab.leave": "Congés",
    "tab.documents": "Documents",
    "tab.history": "Historique",
    "position.title": "Poste",
    "position.missing": "Ce poste n'est pas dans les exemples.",
    "position.vacant": "Vacant",
    "position.filled": "Comblé",
    "field.preferred": "Nom usuel",
    "field.legal": "Nom légal",
    "field.tax": "Province d'impôt",
    "field.primary": "Principale",
    "field.rate": "Taux",
    "field.agreement": "Convention",
    "field.manager": "Gestionnaire",
    "field.status": "État",
    "field.fte": "ETP",
    "field.yes": "Oui",
    "field.no": "Non",
    "positions.title": "Postes",
    "positions.empty": "Aucun poste à afficher.",
    "lang.switch": "English",
    "nav.skip": "Aller au contenu",
  },
} as const;

export type CoreMessageKey = keyof (typeof MESSAGES)["en-CA"];

export function coreMessageKeys(): CoreMessageKey[] {
  return Object.keys(MESSAGES["en-CA"]) as CoreMessageKey[];
}

export function ct(locale: Locale, key: CoreMessageKey): string {
  const text = MESSAGES[locale][key];
  if (!text) throw new CanDoError("INTERFACE_LANGUAGE_NOT_AVAILABLE");
  return text;
}

export function assertCoreLocales(): void {
  const english = Object.keys(MESSAGES["en-CA"]).sort().join("\n");
  const french = Object.keys(MESSAGES["fr-CA"]).sort().join("\n");
  if (english !== french) throw new CanDoError("INTERFACE_LANGUAGE_NOT_AVAILABLE");
}
