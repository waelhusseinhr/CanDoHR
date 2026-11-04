/** Screen copy. The organization's own words are never translated here. */

export const screen = {
  "en-CA": {
    statement:
      "Total rewards: pay {pay}, employer Canada Pension Plan {cpp}, employer Employment Insurance {ei}, pension {pension}, benefits {benefits}, time off {timeOff}.",
    option: "Option {code} costs {amount} each pay.",
    comparison: "Compare the per-pay cost of each option. A person chooses.",
  },
  "fr-CA": {
    statement:
      "Rémunération globale : salaire {pay}, Régime de pensions du Canada de l'employeur {cpp}, assurance-emploi de l'employeur {ei}, régime de retraite {pension}, avantages sociaux {benefits}, congés {timeOff}.",
    option: "L'option {code} coûte {amount} chaque paie.",
    comparison: "Comparez le coût par paie de chaque option. Une personne choisit.",
  },
} as const;

export type ScreenLang = keyof typeof screen;

export function fill(template: string, values: Record<string, string>): string {
  let out = template;
  for (const [key, value] of Object.entries(values)) {
    out = out.split(`{${key}}`).join(value);
  }
  return out;
}
