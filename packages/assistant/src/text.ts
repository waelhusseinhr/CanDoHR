/** Screen copy. The organization's own words are never translated here. */

export const screen = {
  "en-CA": {
    cannotAccess: "You cannot access that record.",
    notCovered: "The agreement does not cover this. Contact labour relations.",
    assistantOff: "The assistant is off.",
    estimate: "This is an estimate.",
    noRecommendation: "The assistant does not recommend a benefit election.",
    bookletGap: "The booklet does not cover this.",
    aiSuggestion: "This suggestion is from the assistant. You can edit it.",
    draft: "This is a draft. Nothing is saved until you submit it.",
  },
  "fr-CA": {
    cannotAccess: "Vous ne pouvez pas consulter ce dossier.",
    notCovered: "La convention ne couvre pas ceci. Communiquez avec les relations de travail.",
    assistantOff: "L'assistant est éteint.",
    estimate: "Ceci est une estimation.",
    noRecommendation: "L'assistant ne recommande pas un choix d'avantages.",
    bookletGap: "Le livret ne couvre pas ceci.",
    aiSuggestion: "Cette suggestion vient de l'assistant. Vous pouvez la modifier.",
    draft: "Ceci est un brouillon. Rien n'est enregistré tant que vous ne le soumettez pas.",
  },
} as const;

export type ScreenLang = keyof typeof screen;
