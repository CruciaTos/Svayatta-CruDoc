import 'package:doctor_management_app/features/homeopathy/data/repertory/rubric.dart';

// Same format as `repertory_part_mind.dart` (read the header there).
//
// NOTE: written by a language model and NOT yet reviewed by a homeopath.
// It must be reviewed before release.

/// Chapter "Generals": modalities, thermals, desires and aversions, thirst,
/// sleep, perspiration and constitution.
const List<Rubric> kRepertoryGenerals = [
  // Modalities.
  Rubric(
    id: 'g-cold-agg',
    chapter: 'Generals',
    path: 'Generalities > Cold > agg.',
    remedies: {
      'Ars.': 3,
      'Calc.': 3,
      'Hep.': 3,
      'Kali-c.': 3,
      'Nux-v.': 3,
      'Sil.': 3,
      'Rhus-t.': 3,
      'Dulc.': 3,
      'Bar-c.': 3,
      'Caust.': 3,
      'Acon.': 2,
    },
  ),
  Rubric(
    id: 'g-cold-amel',
    chapter: 'Generals',
    path: 'Generalities > Cold > amel.',
    remedies: {
      'Apis': 3,
      'Led.': 3,
      'Puls.': 3,
      'Sec.': 3,
      'Iod.': 3,
      'Sulph.': 2,
    },
  ),
  Rubric(
    id: 'g-warm-agg',
    chapter: 'Generals',
    path: 'Generalities > Warm > agg.',
    remedies: {
      'Apis': 3,
      'Iod.': 3,
      'Lach.': 3,
      'Puls.': 3,
      'Sulph.': 3,
      'Glon.': 3,
      'Nat-m.': 2,
    },
  ),
  Rubric(
    id: 'g-warm-amel',
    chapter: 'Generals',
    path: 'Generalities > Warm > amel.',
    remedies: {
      'Ars.': 3,
      'Mag-p.': 3,
      'Rhus-t.': 3,
      'Sil.': 3,
      'Hep.': 3,
      'Nux-v.': 3,
    },
  ),
  Rubric(
    id: 'g-air-open-amel',
    chapter: 'Generals',
    path: 'Generalities > Air > open > amel.',
    remedies: {'Puls.': 3, 'All-c.': 3, 'Apis': 3, 'Iod.': 3},
  ),
  Rubric(
    id: 'g-draught-agg',
    chapter: 'Generals',
    path: 'Generalities > Air > draught of air > agg.',
    remedies: {'Hep.': 3, 'Sil.': 3, 'Nux-v.': 3, 'Chin.': 3, 'Calc.': 2},
  ),
  Rubric(
    id: 'g-motion-agg',
    chapter: 'Generals',
    path: 'Generalities > Motion > agg.',
    remedies: {'Bry.': 3, 'Cocc.': 3, 'Colch.': 3, 'Nux-v.': 2},
  ),
  Rubric(
    id: 'g-motion-amel',
    chapter: 'Generals',
    path: 'Generalities > Motion > amel.',
    remedies: {'Rhus-t.': 3, 'Puls.': 3, 'Ferr.': 3, 'Ruta': 2},
  ),
  Rubric(
    id: 'g-motion-begin-agg',
    chapter: 'Generals',
    path: 'Generalities > Motion > beginning of > agg.',
    remedies: {'Rhus-t.': 3, 'Puls.': 3, 'Lyc.': 2, 'Caust.': 2, 'Con.': 2},
  ),
  Rubric(
    id: 'g-morning-agg',
    chapter: 'Generals',
    path: 'Generalities > Morning > agg.',
    remedies: {'Bry.': 3, 'Lach.': 3, 'Nat-m.': 3, 'Nux-v.': 3, 'Sulph.': 3},
  ),
  Rubric(
    id: 'g-afternoon-4-8-agg',
    chapter: 'Generals',
    path: 'Generalities > Afternoon, 4 to 8 p.m. > agg.',
    remedies: {'Lyc.': 3, 'Hell.': 3},
  ),
  Rubric(
    id: 'g-night-agg',
    chapter: 'Generals',
    path: 'Generalities > Night > agg.',
    remedies: {'Ars.': 3, 'Merc.': 3, 'Rhus-t.': 3, 'Syph.': 3, 'Puls.': 2},
  ),
  Rubric(
    id: 'g-midnight-after-agg',
    chapter: 'Generals',
    path: 'Generalities > Midnight, after > agg.',
    remedies: {'Ars.': 3, 'Acon.': 3, 'Samb.': 3, 'Rhus-t.': 2},
  ),
  Rubric(
    id: 'g-eating-after-agg',
    chapter: 'Generals',
    path: 'Generalities > Eating, after > agg.',
    remedies: {'Nux-v.': 3, 'Lyc.': 3, 'Carb-v.': 3, 'Puls.': 3, 'Chin.': 2},
  ),
  Rubric(
    id: 'g-eating-amel',
    chapter: 'Generals',
    path: 'Generalities > Eating, after > amel.',
    remedies: {'Anac.': 3, 'Chel.': 3, 'Iod.': 3},
  ),
  Rubric(
    id: 'g-damp-weather-agg',
    chapter: 'Generals',
    path: 'Generalities > Weather > damp > agg.',
    remedies: {'Dulc.': 3, 'Rhus-t.': 3, 'Nat-s.': 3, 'Calc.': 2},
  ),
  Rubric(
    id: 'g-weather-change-agg',
    chapter: 'Generals',
    path: 'Generalities > Weather > change of > agg.',
    remedies: {'Dulc.': 3, 'Rhod.': 3, 'Calc.': 2, 'Merc.': 2},
  ),
  Rubric(
    id: 'g-bathing-agg',
    chapter: 'Generals',
    path: 'Generalities > Bathing > agg.',
    remedies: {'Ant-c.': 3, 'Sulph.': 3, 'Calc.': 2, 'Rhus-t.': 2},
  ),
  Rubric(
    id: 'g-pressure-amel',
    chapter: 'Generals',
    path: 'Generalities > Pressure > amel.',
    remedies: {'Bry.': 3, 'Coloc.': 3, 'Mag-p.': 3},
  ),
  Rubric(
    id: 'g-touch-agg',
    chapter: 'Generals',
    path: 'Generalities > Touch > agg.',
    remedies: {'Bell.': 3, 'Hep.': 3, 'Lach.': 3, 'Apis': 3, 'Chin.': 3},
  ),
  Rubric(
    id: 'g-sun-agg',
    chapter: 'Generals',
    path: 'Generalities > Sun, exposure to > agg.',
    remedies: {'Glon.': 3, 'Lach.': 3, 'Nat-c.': 3, 'Bell.': 2, 'Nat-m.': 2},
  ),
  Rubric(
    id: 'g-mental-exertion-agg',
    chapter: 'Generals',
    path: 'Generalities > Mental exertion > agg.',
    remedies: {'Nux-v.': 3, 'Calc.': 3, 'Nat-c.': 3, 'Phos.': 2},
  ),
  Rubric(
    id: 'g-pain-sensitive',
    chapter: 'Generals',
    path: 'Generalities > Pain > sensitive to',
    remedies: {'Cham.': 3, 'Coff.': 3, 'Acon.': 3, 'Hep.': 2},
  ),

  // Thermals and constitution.
  Rubric(
    id: 'g-chilly',
    chapter: 'Generals',
    path: 'Generalities > Heat, vital, lack of (chilly patient)',
    remedies: {
      'Ars.': 3,
      'Calc.': 3,
      'Hep.': 3,
      'Kali-c.': 3,
      'Nux-v.': 3,
      'Psor.': 3,
      'Sil.': 3,
      'Sep.': 2,
    },
  ),
  Rubric(
    id: 'g-hot',
    chapter: 'Generals',
    path: 'Generalities > Heat, vital, excess of (hot patient)',
    remedies: {'Sulph.': 3, 'Iod.': 3, 'Puls.': 3, 'Apis': 3, 'Lach.': 2},
  ),
  Rubric(
    id: 'g-weakness',
    chapter: 'Generals',
    path: 'Generalities > Weakness',
    remedies: {
      'Ars.': 3,
      'Chin.': 3,
      'Ph-ac.': 3,
      'Verat.': 3,
      'Phos.': 3,
      'Carb-v.': 2,
      'Gels.': 2,
    },
  ),
  Rubric(
    id: 'g-emaciation',
    chapter: 'Generals',
    path: 'Generalities > Emaciation',
    remedies: {'Iod.': 3, 'Nat-m.': 3, 'Abrot.': 3, 'Tub.': 3},
  ),
  Rubric(
    id: 'g-obesity',
    chapter: 'Generals',
    path: 'Generalities > Obesity',
    remedies: {'Calc.': 3, 'Graph.': 3, 'Ant-c.': 2, 'Puls.': 2},
  ),

  // Desires, aversions and thirst.
  Rubric(
    id: 'g-desire-sweets',
    chapter: 'Generals',
    path: 'Food > Desires > sweets',
    remedies: {'Arg-n.': 3, 'Sulph.': 3, 'Lyc.': 3, 'Calc.': 2, 'Kali-c.': 2},
  ),
  Rubric(
    id: 'g-desire-salt',
    chapter: 'Generals',
    path: 'Food > Desires > salt',
    remedies: {'Nat-m.': 3, 'Verat.': 3, 'Carb-v.': 3, 'Phos.': 2, 'Calc.': 2},
  ),
  Rubric(
    id: 'g-desire-cold-drinks',
    chapter: 'Generals',
    path: 'Food > Desires > cold drinks',
    remedies: {'Phos.': 3, 'Verat.': 3, 'Bry.': 3, 'Acon.': 3},
  ),
  Rubric(
    id: 'g-desire-warm-drinks',
    chapter: 'Generals',
    path: 'Food > Desires > warm drinks',
    remedies: {'Chel.': 3, 'Lyc.': 3, 'Ars.': 2},
  ),
  Rubric(
    id: 'g-desire-sour',
    chapter: 'Generals',
    path: 'Food > Desires > sour, acids',
    remedies: {'Hep.': 3, 'Sep.': 3, 'Ars.': 2},
  ),
  Rubric(
    id: 'g-desire-spicy',
    chapter: 'Generals',
    path: 'Food > Desires > spicy, condiments',
    remedies: {'Hep.': 3, 'Nux-v.': 3, 'Sulph.': 3},
  ),
  Rubric(
    id: 'g-aversion-fat',
    chapter: 'Generals',
    path: 'Food > Aversion > fat, rich food',
    remedies: {'Puls.': 3, 'Carb-v.': 2, 'Chin.': 2},
  ),
  Rubric(
    id: 'g-thirstless',
    chapter: 'Generals',
    path: 'Food > Thirstless',
    remedies: {'Puls.': 3, 'Apis': 3, 'Gels.': 3, 'Ip.': 3, 'Ant-t.': 3},
  ),
  Rubric(
    id: 'g-thirst-extreme',
    chapter: 'Generals',
    path: 'Food > Thirst > extreme, large quantities',
    remedies: {'Acon.': 3, 'Bry.': 3, 'Phos.': 3, 'Verat.': 3, 'Sulph.': 2},
  ),

  // Sleep.
  Rubric(
    id: 'g-sleeplessness',
    chapter: 'Generals',
    path: 'Sleep > Sleeplessness',
    remedies: {
      'Acon.': 3,
      'Ars.': 3,
      'Coff.': 3,
      'Nux-v.': 3,
      'Sulph.': 2,
      'Puls.': 2,
    },
  ),
  Rubric(
    id: 'g-waking-3am',
    chapter: 'Generals',
    path: 'Sleep > Waking > 3 a.m.',
    remedies: {'Nux-v.': 3, 'Kali-c.': 3, 'Ars.': 2},
  ),
  Rubric(
    id: 'g-sleepiness-day',
    chapter: 'Generals',
    path: 'Sleep > Sleepiness > daytime',
    remedies: {'Gels.': 3, 'Nux-m.': 3, 'Op.': 3, 'Ph-ac.': 2},
  ),

  // Perspiration.
  Rubric(
    id: 'g-sweat-night',
    chapter: 'Generals',
    path: 'Perspiration > Night',
    remedies: {
      'Calc.': 3,
      'Chin.': 3,
      'Merc.': 3,
      'Phos.': 3,
      'Sil.': 3,
      'Sulph.': 2,
    },
  ),
  Rubric(
    id: 'g-sweat-head',
    chapter: 'Generals',
    path: 'Perspiration > Head',
    remedies: {'Calc.': 3, 'Sil.': 3, 'Merc.': 2, 'Sulph.': 2},
  ),
  Rubric(
    id: 'g-sweat-offensive',
    chapter: 'Generals',
    path: 'Perspiration > Offensive',
    remedies: {'Hep.': 3, 'Merc.': 3, 'Sulph.': 2, 'Sil.': 2},
  ),
  Rubric(
    id: 'g-sweat-cold',
    chapter: 'Generals',
    path: 'Perspiration > Cold',
    remedies: {'Verat.': 3, 'Camph.': 3, 'Carb-v.': 3},
  ),
];
