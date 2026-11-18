import 'package:doctor_management_app/features/homeopathy/data/repertory/rubric.dart';

// REPERTORY DATA FILE FORMAT (copy this header into a new data file)
//
// A data file is one `const List<Rubric>`. Add the list to
// `allRepertoryParts` in `repertory_registry.dart` (one line); no other code
// changes. Each rubric is:
//
//   Rubric(
//     id: 'm-fear-death',               // unique, never reused or renamed:
//                                       //   saved repertorizations store it
//     chapter: 'Mind',                  // filter chip; keep names consistent
//     path: 'Mind > Fear > death, of',  // breadcrumb, parts joined by ' > ';
//                                       //   the last part is the symptom
//     remedies: {'Acon.': 3, 'Ars.': 3, 'Phos.': 2},
//   )
//
// - Remedy keys are the abbreviations used in `homeopathy_remedies.dart`
//   (case and full stops are ignored). An unknown abbreviation is dropped when
//   the repertory loads, and trips an assert in debug builds.
// - Grades: 1 = plain type, 2 = italic, 3 = bold.
// - Only add content you are sure of; a short, correct rubric beats a long
//   doubtful one. Write rubrics in your own words and from your own
//   knowledge; do not copy text from a published repertory.
//
// NOTE: written by a language model and NOT yet reviewed by a homeopath.
// It must be reviewed before release.

/// Chapter "Mind": fears, anxiety, anger, grief, mood and behaviour.
const List<Rubric> kRepertoryMind = [
  Rubric(
    id: 'm-fear-death',
    chapter: 'Mind',
    path: 'Mind > Fear > death, of',
    remedies: {'Acon.': 3, 'Ars.': 3, 'Phos.': 2, 'Calc.': 2},
  ),
  Rubric(
    id: 'm-fear-dark',
    chapter: 'Mind',
    path: 'Mind > Fear > dark, of',
    remedies: {'Stram.': 3, 'Calc.': 2, 'Phos.': 2, 'Carb-v.': 2, 'Puls.': 2},
  ),
  Rubric(
    id: 'm-fear-alone',
    chapter: 'Mind',
    path: 'Mind > Fear > alone, of being',
    remedies: {'Ars.': 3, 'Kali-c.': 3, 'Lyc.': 3, 'Con.': 2, 'Phos.': 2},
  ),
  Rubric(
    id: 'm-fear-robbers',
    chapter: 'Mind',
    path: 'Mind > Fear > robbers, of',
    remedies: {'Ars.': 3, 'Nat-m.': 3},
  ),
  Rubric(
    id: 'm-fear-thunderstorm',
    chapter: 'Mind',
    path: 'Mind > Fear > thunderstorm, of',
    remedies: {'Phos.': 3, 'Rhod.': 3, 'Nat-c.': 2, 'Sep.': 2},
  ),
  Rubric(
    id: 'm-fear-insanity',
    chapter: 'Mind',
    path: 'Mind > Fear > insanity, of',
    remedies: {'Calc.': 3, 'Cimic.': 2, 'Lil-t.': 2},
  ),
  Rubric(
    id: 'm-anxiety',
    chapter: 'Mind',
    path: 'Mind > Anxiety',
    remedies: {
      'Acon.': 3,
      'Ars.': 3,
      'Calc.': 3,
      'Phos.': 3,
      'Puls.': 3,
      'Rhus-t.': 2,
      'Lyc.': 2,
    },
  ),
  Rubric(
    id: 'm-anxiety-health',
    chapter: 'Mind',
    path: 'Mind > Anxiety > health, about',
    remedies: {'Ars.': 3, 'Phos.': 3, 'Nit-ac.': 3, 'Calc.': 2},
  ),
  Rubric(
    id: 'm-anticipation',
    chapter: 'Mind',
    path: 'Mind > Anticipation, complaints from',
    remedies: {'Arg-n.': 3, 'Gels.': 3, 'Lyc.': 3},
  ),
  Rubric(
    id: 'm-anger',
    chapter: 'Mind',
    path: 'Mind > Anger, irascibility',
    remedies: {
      'Cham.': 3,
      'Nux-v.': 3,
      'Staph.': 3,
      'Bry.': 3,
      'Aur.': 3,
      'Lyc.': 2,
      'Ars.': 2,
      'Sep.': 2,
    },
  ),
  Rubric(
    id: 'm-ailments-anger',
    chapter: 'Mind',
    path: 'Mind > Ailments from > anger, vexation, indignation',
    remedies: {'Coloc.': 3, 'Staph.': 3, 'Cham.': 3, 'Bry.': 3, 'Nux-v.': 3},
  ),
  Rubric(
    id: 'm-ailments-grief',
    chapter: 'Mind',
    path: 'Mind > Ailments from > grief',
    remedies: {'Ign.': 3, 'Nat-m.': 3, 'Ph-ac.': 3, 'Aur.': 3, 'Staph.': 2},
  ),
  Rubric(
    id: 'm-ailments-love',
    chapter: 'Mind',
    path: 'Mind > Ailments from > disappointed love',
    remedies: {'Ign.': 3, 'Nat-m.': 3, 'Ph-ac.': 3, 'Hyos.': 2, 'Aur.': 2},
  ),
  Rubric(
    id: 'm-ailments-fright',
    chapter: 'Mind',
    path: 'Mind > Ailments from > fright',
    remedies: {'Acon.': 3, 'Op.': 3, 'Gels.': 3, 'Ign.': 2},
  ),
  Rubric(
    id: 'm-consolation-agg',
    chapter: 'Mind',
    path: 'Mind > Consolation > agg.',
    remedies: {'Nat-m.': 3, 'Sep.': 3, 'Sil.': 3, 'Lyc.': 2, 'Ign.': 1},
  ),
  Rubric(
    id: 'm-consolation-amel',
    chapter: 'Mind',
    path: 'Mind > Consolation > amel.',
    remedies: {'Puls.': 3, 'Phos.': 2},
  ),
  Rubric(
    id: 'm-company-aversion',
    chapter: 'Mind',
    path: 'Mind > Company > aversion to',
    remedies: {'Nat-m.': 3, 'Sep.': 3, 'Aur.': 3, 'Ign.': 2, 'Con.': 2},
  ),
  Rubric(
    id: 'm-company-desire',
    chapter: 'Mind',
    path: 'Mind > Company > desire for',
    remedies: {'Phos.': 3, 'Puls.': 3, 'Ars.': 3, 'Lyc.': 2},
  ),
  Rubric(
    id: 'm-restlessness',
    chapter: 'Mind',
    path: 'Mind > Restlessness',
    remedies: {
      'Ars.': 3,
      'Rhus-t.': 3,
      'Acon.': 3,
      'Tarent.': 3,
      'Cham.': 2,
      'Zinc.': 2,
    },
  ),
  Rubric(
    id: 'm-weeping',
    chapter: 'Mind',
    path: 'Mind > Weeping, tearful mood',
    remedies: {
      'Puls.': 3,
      'Ign.': 3,
      'Nat-m.': 3,
      'Sep.': 3,
      'Calc.': 2,
      'Phos.': 2,
      'Lyc.': 2,
    },
  ),
  Rubric(
    id: 'm-irritability',
    chapter: 'Mind',
    path: 'Mind > Irritability',
    remedies: {
      'Nux-v.': 3,
      'Cham.': 3,
      'Bry.': 3,
      'Sep.': 3,
      'Lyc.': 3,
      'Hep.': 3,
      'Sulph.': 2,
    },
  ),
  Rubric(
    id: 'm-irritability-children',
    chapter: 'Mind',
    path: 'Mind > Irritability > children, in',
    remedies: {'Cham.': 3, 'Cina': 3, 'Ant-c.': 2},
  ),
  Rubric(
    id: 'm-fastidious',
    chapter: 'Mind',
    path: 'Mind > Fastidious',
    remedies: {'Ars.': 3, 'Nux-v.': 2, 'Sil.': 2},
  ),
  Rubric(
    id: 'm-jealousy',
    chapter: 'Mind',
    path: 'Mind > Jealousy',
    remedies: {'Lach.': 3, 'Hyos.': 3, 'Apis': 3, 'Nux-v.': 2},
  ),
  Rubric(
    id: 'm-indifference',
    chapter: 'Mind',
    path: 'Mind > Indifference, apathy',
    remedies: {'Ph-ac.': 3, 'Phos.': 3, 'Sep.': 3},
  ),
  Rubric(
    id: 'm-sensitive-noise',
    chapter: 'Mind',
    path: 'Mind > Sensitive > noise, to',
    remedies: {'Coff.': 3, 'Nux-v.': 3, 'Cham.': 3, 'Ign.': 2, 'Sil.': 2},
  ),
  Rubric(
    id: 'm-timidity',
    chapter: 'Mind',
    path: 'Mind > Timidity',
    remedies: {'Lyc.': 3, 'Gels.': 3, 'Sil.': 3, 'Puls.': 2, 'Calc.': 2},
  ),
  Rubric(
    id: 'm-confidence-want',
    chapter: 'Mind',
    path: 'Mind > Confidence, want of self-',
    remedies: {'Lyc.': 3, 'Sil.': 3, 'Bar-c.': 3, 'Arg-n.': 2},
  ),
  Rubric(
    id: 'm-dullness',
    chapter: 'Mind',
    path: 'Mind > Dullness, sluggish comprehension',
    remedies: {'Bar-c.': 3, 'Gels.': 3, 'Ph-ac.': 3, 'Hell.': 3, 'Phos.': 2},
  ),
  Rubric(
    id: 'm-forgetful',
    chapter: 'Mind',
    path: 'Mind > Forgetful',
    remedies: {'Anac.': 3, 'Lyc.': 3, 'Bar-c.': 3, 'Phos.': 3, 'Nat-m.': 2},
  ),
  Rubric(
    id: 'm-suicidal',
    chapter: 'Mind',
    path: 'Mind > Suicidal disposition',
    remedies: {'Aur.': 3, 'Ars.': 3, 'Nat-s.': 3, 'Nux-v.': 2},
  ),
  Rubric(
    id: 'm-sadness',
    chapter: 'Mind',
    path: 'Mind > Sadness, depression',
    remedies: {
      'Aur.': 3,
      'Ign.': 3,
      'Nat-m.': 3,
      'Puls.': 3,
      'Sep.': 3,
      'Ph-ac.': 2,
      'Ars.': 2,
    },
  ),
  Rubric(
    id: 'm-mood-changeable',
    chapter: 'Mind',
    path: 'Mind > Mood > changeable',
    remedies: {'Puls.': 3, 'Ign.': 3, 'Croc.': 3},
  ),
  Rubric(
    id: 'm-haughty',
    chapter: 'Mind',
    path: 'Mind > Haughty',
    remedies: {'Plat.': 3, 'Lyc.': 3, 'Sulph.': 3, 'Verat.': 2},
  ),
  Rubric(
    id: 'm-talkative',
    chapter: 'Mind',
    path: 'Mind > Talkative, loquacity',
    remedies: {'Lach.': 3, 'Stram.': 3, 'Hyos.': 3, 'Agar.': 2},
  ),
  Rubric(
    id: 'm-rage',
    chapter: 'Mind',
    path: 'Mind > Rage, fury',
    remedies: {'Bell.': 3, 'Hyos.': 3, 'Stram.': 3},
  ),
  Rubric(
    id: 'm-mildness',
    chapter: 'Mind',
    path: 'Mind > Mildness, yielding disposition',
    remedies: {'Puls.': 3, 'Phos.': 2},
  ),
  Rubric(
    id: 'm-dictatorial',
    chapter: 'Mind',
    path: 'Mind > Dictatorial, domineering',
    remedies: {'Lyc.': 3, 'Nux-v.': 2},
  ),
  Rubric(
    id: 'm-hurry',
    chapter: 'Mind',
    path: 'Mind > Hurry, haste',
    remedies: {'Arg-n.': 3, 'Med.': 3, 'Lil-t.': 2},
  ),
];
