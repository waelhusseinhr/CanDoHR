/** Screen copy. The organization's own words are never translated here. */

export const screen = {
  "en-CA": {
    commentsOnly: "This position is open for comments. It is not rated.",
    nudge: "A check-in is due.",
    youSaid: "You said, we did.",
    recognitionPrivate: "This recognition is private until the person recognized asks to share it.",
    speakUp: "You can use the speak-up channel. Crisis lines are listed with this survey.",
    noPlayer: "Courses open in the organization's learning system. CanDo does not play them.",
  },
  "fr-CA": {
    commentsOnly: "Ce poste est ouvert aux commentaires. Il n'est pas noté.",
    nudge: "Une rencontre est due.",
    youSaid: "Vous l'avez dit, nous l'avons fait.",
    recognitionPrivate: "Cette reconnaissance reste privée jusqu'à ce que la personne reconnue demande de la partager.",
    speakUp: "Vous pouvez utiliser le canal pour parler. Les lignes d'écoute sont indiquées avec ce sondage.",
    noPlayer: "Les cours s'ouvrent dans le système d'apprentissage de l'organisation. CanDo ne les joue pas.",
  },
} as const;

export type ScreenLang = keyof typeof screen;
