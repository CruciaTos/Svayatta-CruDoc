import 'package:doctor_management_app/features/homeopathy/data/repertory/rubric.dart';

// Same format as `repertory_part_mind.dart` (read the header there).
//
// NOTE: written by a language model and NOT yet reviewed by a homeopath.
// It must be reviewed before release.

/// Chapter "Particulars": common local complaints by body part.
const List<Rubric> kRepertoryParticulars = [
  // Head, eyes, nose, mouth.
  Rubric(
    id: 'p-head-periodical',
    chapter: 'Particulars',
    path: 'Head > Pain > periodical',
    remedies: {'Chin.': 3, 'Nat-m.': 3, 'Ars.': 3, 'Sil.': 2},
  ),
  Rubric(
    id: 'p-head-throbbing',
    chapter: 'Particulars',
    path: 'Head > Pain > throbbing',
    remedies: {'Bell.': 3, 'Glon.': 3, 'Nat-m.': 2},
  ),
  Rubric(
    id: 'p-head-nail',
    chapter: 'Particulars',
    path: 'Head > Pain > nail, as if a, driven in',
    remedies: {'Ign.': 3, 'Coff.': 3, 'Thuj.': 3},
  ),
  Rubric(
    id: 'p-eye-conjunctivitis',
    chapter: 'Particulars',
    path: 'Eyes > Inflammation > conjunctiva',
    remedies: {'Euphr.': 3, 'Puls.': 3, 'Merc.': 3, 'Apis': 2},
  ),
  Rubric(
    id: 'p-eye-photophobia',
    chapter: 'Particulars',
    path: 'Eyes > Photophobia',
    remedies: {'Bell.': 3, 'Euphr.': 3, 'Acon.': 2},
  ),
  Rubric(
    id: 'p-nose-coryza-excoriating',
    chapter: 'Particulars',
    path: 'Nose > Coryza > watery, excoriating',
    remedies: {'All-c.': 3, 'Ars.': 3, 'Arum-t.': 3},
  ),
  Rubric(
    id: 'p-nose-discharge-yellow-green',
    chapter: 'Particulars',
    path: 'Nose > Discharge > yellow-green, thick',
    remedies: {'Puls.': 3, 'Kali-bi.': 3, 'Kali-s.': 2, 'Merc.': 2},
  ),
  Rubric(
    id: 'p-mouth-dry-thirstless',
    chapter: 'Particulars',
    path: 'Mouth > Dryness > without thirst',
    remedies: {'Nux-m.': 3, 'Puls.': 3, 'Apis': 2},
  ),
  Rubric(
    id: 'p-mouth-taste-bitter',
    chapter: 'Particulars',
    path: 'Mouth > Taste > bitter',
    remedies: {'Bry.': 3, 'Puls.': 3, 'Nux-v.': 2, 'Merc.': 2},
  ),
  Rubric(
    id: 'p-teeth-cold-amel',
    chapter: 'Particulars',
    path: 'Teeth > Pain > cold > amel.',
    remedies: {'Coff.': 3, 'Puls.': 3, 'Bry.': 2},
  ),

  // Cough and chest.
  Rubric(
    id: 'p-cough-dry',
    chapter: 'Particulars',
    path: 'Cough > dry',
    remedies: {
      'Acon.': 3,
      'Bry.': 3,
      'Hyos.': 3,
      'Phos.': 3,
      'Rumx.': 3,
      'Nux-v.': 2,
    },
  ),
  Rubric(
    id: 'p-cough-loose',
    chapter: 'Particulars',
    path: 'Cough > loose, rattling',
    remedies: {'Ant-t.': 3, 'Puls.': 3, 'Hep.': 2, 'Sulph.': 2},
  ),
  Rubric(
    id: 'p-cough-whooping',
    chapter: 'Particulars',
    path: 'Cough > whooping',
    remedies: {'Dros.': 3, 'Cupr.': 3, 'Ip.': 3, 'Cocc-c.': 2, 'Cina': 2},
  ),
  Rubric(
    id: 'p-cough-lying-agg',
    chapter: 'Particulars',
    path: 'Cough > lying > agg.',
    remedies: {'Puls.': 3, 'Hyos.': 3, 'Dros.': 2, 'Phos.': 2},
  ),
  Rubric(
    id: 'p-resp-asthmatic',
    chapter: 'Particulars',
    path: 'Respiration > Asthmatic',
    remedies: {'Ars.': 3, 'Ip.': 3, 'Ant-t.': 3, 'Samb.': 2},
  ),
  Rubric(
    id: 'p-chest-pain-stitching',
    chapter: 'Particulars',
    path: 'Chest > Pain > stitching',
    remedies: {'Bry.': 3, 'Kali-c.': 3, 'Ran-b.': 2},
  ),

  // Stomach, abdomen, rectum.
  Rubric(
    id: 'p-stomach-nausea',
    chapter: 'Particulars',
    path: 'Stomach > Nausea',
    remedies: {'Ip.': 3, 'Ars.': 3, 'Nux-v.': 3, 'Puls.': 2, 'Sep.': 2},
  ),
  Rubric(
    id: 'p-stomach-vomiting',
    chapter: 'Particulars',
    path: 'Stomach > Vomiting',
    remedies: {'Ars.': 3, 'Ip.': 3, 'Verat.': 3, 'Phos.': 2, 'Nux-v.': 2},
  ),
  Rubric(
    id: 'p-stomach-pain-burning',
    chapter: 'Particulars',
    path: 'Stomach > Pain > burning',
    remedies: {'Ars.': 3, 'Phos.': 3, 'Carb-v.': 2},
  ),
  Rubric(
    id: 'p-stomach-eructation-sour',
    chapter: 'Particulars',
    path: 'Stomach > Eructations > sour',
    remedies: {'Carb-v.': 3, 'Nux-v.': 3, 'Lyc.': 3, 'Nat-p.': 3},
  ),
  Rubric(
    id: 'p-abdomen-distension-eating',
    chapter: 'Particulars',
    path: 'Abdomen > Distension > eating, after',
    remedies: {'Lyc.': 3, 'Carb-v.': 3, 'Chin.': 3, 'Nux-v.': 2},
  ),
  Rubric(
    id: 'p-abdomen-colic-bending',
    chapter: 'Particulars',
    path: 'Abdomen > Pain > cramping > bending double amel.',
    remedies: {'Coloc.': 3, 'Mag-p.': 3, 'Dios.': 3, 'Cham.': 2},
  ),
  Rubric(
    id: 'p-rectum-constipation',
    chapter: 'Particulars',
    path: 'Rectum > Constipation',
    remedies: {'Alum.': 3, 'Bry.': 3, 'Nux-v.': 3, 'Op.': 3, 'Sil.': 2},
  ),
  Rubric(
    id: 'p-stool-soft-difficult',
    chapter: 'Particulars',
    path: 'Stool > soft, yet difficult to expel',
    remedies: {'Alum.': 3, 'Sil.': 3},
  ),
  Rubric(
    id: 'p-diarrhoea-morning',
    chapter: 'Particulars',
    path: 'Diarrhoea > morning, driving out of bed',
    remedies: {'Sulph.': 3, 'Rumx.': 3, 'Nat-s.': 3, 'Podo.': 3, 'Aloe': 3},
  ),
  Rubric(
    id: 'p-diarrhoea-eating-after',
    chapter: 'Particulars',
    path: 'Diarrhoea > eating, after',
    remedies: {'Ars.': 3, 'Chin.': 3, 'Ferr.': 3},
  ),
  Rubric(
    id: 'p-diarrhoea-painless',
    chapter: 'Particulars',
    path: 'Diarrhoea > painless',
    remedies: {'Chin.': 3, 'Phos.': 3, 'Ferr.': 3, 'Podo.': 2},
  ),
  Rubric(
    id: 'p-diarrhoea-anticipation',
    chapter: 'Particulars',
    path: 'Diarrhoea > anticipation, from',
    remedies: {'Arg-n.': 3, 'Gels.': 3},
  ),

  // Urinary and female.
  Rubric(
    id: 'p-urine-burning',
    chapter: 'Particulars',
    path: 'Urine > Burning, during urination',
    remedies: {'Canth.': 3, 'Merc-c.': 2, 'Apis': 2},
  ),
  Rubric(
    id: 'p-urine-involuntary-cough',
    chapter: 'Particulars',
    path: 'Urine > Involuntary > coughing, when',
    remedies: {'Caust.': 3, 'Puls.': 3, 'Sep.': 2},
  ),
  Rubric(
    id: 'p-bladder-enuresis',
    chapter: 'Particulars',
    path: 'Bladder > Enuresis, night',
    remedies: {'Equis.': 3, 'Caust.': 3, 'Sep.': 3, 'Puls.': 2, 'Cina': 2},
  ),
  Rubric(
    id: 'p-menses-delayed',
    chapter: 'Particulars',
    path: 'Female > Menses > delayed, late',
    remedies: {'Puls.': 3, 'Graph.': 3, 'Sep.': 2},
  ),
  Rubric(
    id: 'p-menses-profuse',
    chapter: 'Particulars',
    path: 'Female > Menses > profuse',
    remedies: {'Calc.': 3, 'Phos.': 3, 'Sabin.': 3, 'Chin.': 2},
  ),

  // Skin and limbs.
  Rubric(
    id: 'p-skin-itching-warm-bed',
    chapter: 'Particulars',
    path: 'Skin > Itching > warmth of bed agg.',
    remedies: {'Sulph.': 3, 'Merc.': 3, 'Psor.': 3, 'Puls.': 2},
  ),
  Rubric(
    id: 'p-extr-restless-legs',
    chapter: 'Particulars',
    path: 'Extremities > Restlessness > legs',
    remedies: {'Zinc.': 3, 'Rhus-t.': 3, 'Tarent.': 3, 'Ars.': 2},
  ),
  Rubric(
    id: 'p-extr-feet-cold',
    chapter: 'Particulars',
    path: 'Extremities > Coldness > feet',
    remedies: {'Calc.': 3, 'Sil.': 3, 'Sep.': 2},
  ),
  Rubric(
    id: 'p-extr-feet-burning-night',
    chapter: 'Particulars',
    path: 'Extremities > Heat > feet, burning, at night',
    remedies: {'Sulph.': 3, 'Med.': 3},
  ),
];
