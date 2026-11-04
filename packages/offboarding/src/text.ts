/** Screen copy in every launch language. The organization's own words are never translated here. */

export const screen = {
  "en-CA": {
    groupNotice:
      "This ending reaches the group-termination count for this establishment. Prepare the ministry notice.",
    bereavement: "We are sorry for your loss. Payments will be made to the estate.",
    letter: "Your employment ends on {date}.",
    release: "This release is available for you to review.",
    reference: "Reference letter for the period of employment.",
    assetTask: "Recover assigned equipment {id}.",
  },
  "fr-CA": {
    groupNotice:
      "Cette fin atteint le nombre de cessations collectives pour cet établissement. Préparez l'avis au ministère.",
    bereavement: "Nous vous offrons nos condoléances. Les paiements seront versés à la succession.",
    letter: "Votre emploi prend fin le {date}.",
    release: "Cette quittance est prête pour votre lecture.",
    reference: "Lettre de référence pour la période d'emploi.",
    assetTask: "Récupérer l'équipement assigné {id}.",
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
