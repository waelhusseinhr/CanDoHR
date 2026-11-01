import { CanDoError } from "@candohr/shared";

export const LOCALES = ["en-CA", "fr-CA"] as const;
export type Locale = (typeof LOCALES)[number];

const MESSAGES = {
  "en-CA": {
    "people.empty": "No people to show.",
    "session.ended": "Your session has ended. Sign in again.",
    "permission.denied": "You do not have permission to see that.",
    "former.limited": "This login can open your own pay statements, slips and record of employment.",
    "audit.proof": "Inclusion proof",
  },
  "fr-CA": {
    "people.empty": "Aucune personne à afficher.",
    "session.ended": "Votre session est terminée. Ouvrez une session de nouveau.",
    "permission.denied": "Vous n'avez pas la permission de voir cela.",
    "former.limited": "Cette connexion ouvre vos propres relevés de paie, feuillets et relevés d'emploi.",
    "audit.proof": "Preuve d'inclusion",
  },
} as const;

export type MessageKey = keyof (typeof MESSAGES)["en-CA"];

export function messageKeys(): MessageKey[] {
  return Object.keys(MESSAGES["en-CA"]) as MessageKey[];
}

export function t(locale: Locale, key: MessageKey): string {
  const table = MESSAGES[locale];
  const text = table[key];
  if (!text) throw new CanDoError("INTERFACE_LANGUAGE_NOT_AVAILABLE");
  return text;
}

function groupDigits(whole: string, separator: string): string {
  return whole.replace(/\B(?=(\d{3})+(?!\d))/g, separator);
}

/** Money stays a two-decimal string. French Canadian uses a space and a comma: 1 234,56 $. */
export function formatCad(locale: Locale, amount: string): string {
  if (!/^-?\d+\.\d{2}$/.test(amount)) throw new CanDoError("MONEY");
  const negative = amount.startsWith("-");
  const [whole, frac] = amount.replace("-", "").split(".") as [string, string];
  if (locale === "fr-CA") {
    return `${negative ? "-" : ""}${groupDigits(whole, " ")},${frac} $`;
  }
  return `${negative ? "-" : ""}$${groupDigits(whole, ",")}.${frac}`;
}

export function assertLocalesComplete(): void {
  const english = Object.keys(MESSAGES["en-CA"]).sort();
  const french = Object.keys(MESSAGES["fr-CA"]).sort();
  if (english.join("\n") !== french.join("\n")) throw new CanDoError("INTERFACE_LANGUAGE_NOT_AVAILABLE");
}
