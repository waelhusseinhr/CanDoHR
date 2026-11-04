/** Screen copy. The organization's own words are never translated here. */

export const screen = {
  "en-CA": {
    suppressed: "This group is hidden.",
    masked: "Masked",
    unverified: "This entry is still marked check before use.",
    redacted: "Redacted",
    weeklyHoliday: "A holiday that is also weekly overtime: which rate applies?",
    restDayHoliday: "A holiday that is also a second rest day: which rate applies?",
    unresolved: "This combination is not decided.",
  },
  "fr-CA": {
    suppressed: "Ce groupe est caché.",
    masked: "Masqué",
    unverified: "Cette entrée est encore marquée à vérifier avant usage.",
    redacted: "Caviardé",
    weeklyHoliday: "Un jour férié qui est aussi des heures supplémentaires hebdomadaires : quel taux s'applique?",
    restDayHoliday: "Un jour férié qui est aussi un deuxième jour de repos : quel taux s'applique?",
    unresolved: "Cette combinaison n'est pas décidée.",
  },
} as const;

export type ScreenLang = keyof typeof screen;
