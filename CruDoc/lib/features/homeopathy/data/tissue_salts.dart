// The twelve biochemic tissue salts, as Schuessler numbered them.
//
// A different system from classical homeopathy, and worth keeping separate
// rather than folding into the Materia medica: these are prescribed on a
// tissue deficiency rather than on the totality, chosen by indication rather
// than by similimum, given at low decimal potencies, and routinely combined.
// Eight of the twelve are also classical remedies with their own Materia
// medica entries, where the picture given is the classical one — the same
// substance, a different way of reaching for it.
//
// [TissueSalt.remedy] is the exact remedy name from the app's remedy list,
// so prescribing a salt writes the same name as prescribing it classically.
// One patient must not end up with "Ferrum phos" in one record and "Ferrum
// phosphoricum" in another; a test pins every one of these to that list.
//
// The indications are the classical biochemic ones, kept short. They are a
// reminder for someone who already knows the system, not a prescribing
// authority, and the whole file needs a homeopath's read-through before a
// clinic leans on it.

/// One of the twelve, with its number, where it is said to act, and what it
/// is classically reached for.
class TissueSalt {
  const TissueSalt({
    required this.number,
    required this.remedy,
    required this.abbr,
    required this.tissue,
    required this.indications,
    this.potency = '6X',
  });

  /// Schuessler's number, 1 to 12. Clinics and labels both use it, and a
  /// patient often knows the number rather than the name.
  final int number;

  /// The full remedy name, spelled exactly as the app's remedy list spells
  /// it, so a prescription is one name everywhere.
  final String remedy;

  /// The short form a homeopath writes.
  final String abbr;

  /// Where the salt is held to act, in a few words.
  final String tissue;

  /// Classical biochemic indications, shortest first.
  final List<String> indications;

  /// The potency usually dispensed. 6X unless the system calls for another.
  final String potency;

  /// `No. 4 — Ferrum phos.`
  String get label => 'No. $number — $abbr';
}

/// The twelve, in Schuessler's order. The numbering is the system's, so it
/// is never re-sorted.
const List<TissueSalt> kTissueSalts = [
  TissueSalt(
    number: 1,
    remedy: 'Calcarea fluorica',
    abbr: 'Calc fluor.',
    tissue: 'Elastic fibres — bone surfaces, tooth enamel, veins, ligaments',
    indications: [
      'Loss of elasticity in anything that should stretch and recoil',
      'Varicose veins, piles and slack blood vessel walls',
      'Lax ligaments and joints that give way',
      'Hard, knotty swellings on bone, exostoses',
      'Cracked tooth enamel, brittle teeth',
      'Cracks in the skin of the palms and soles',
    ],
  ),
  TissueSalt(
    number: 2,
    remedy: 'Calcarea phosphorica',
    abbr: 'Calc phos.',
    tissue: 'Bone and teeth — wherever new cells are being built',
    indications: [
      'Delayed or difficult growth: teething, bone formation, fontanelles',
      'Slow union of fractures',
      'Growing pains in children and adolescents',
      'Anaemia with poor nutrition and a tired, chilly patient',
      'Spinal curvature in the growing child',
      'Convalescence, where the patient does not pick up',
    ],
  ),
  TissueSalt(
    number: 3,
    remedy: 'Calcarea sulphurica',
    abbr: 'Calc sulph.',
    tissue: 'Connective tissue — the cleanser of discharging surfaces',
    indications: [
      'Suppuration that will not finish: discharge continues after the pus '
          'has a way out',
      'Abscesses, boils and pimples after they have opened',
      'Slow-healing wounds and ulcers with thick yellow discharge',
      'Chronic catarrh with thick, yellow, purulent discharge',
      'Skin that keeps breaking out in crops',
    ],
  ),
  TissueSalt(
    number: 4,
    remedy: 'Ferrum phosphoricum',
    abbr: 'Ferrum phos.',
    tissue: 'Blood — oxygen carriage, and the first stage of inflammation',
    indications: [
      'The first stage of any inflammation, before discharge sets in',
      'Fever of sudden onset with a flushed face and quick pulse',
      'Fresh colds, sore throats and earaches, taken early',
      'Bright red bleeding',
      'Anaemia where iron is tolerated badly',
      'Congestive headache, better for cold applications',
    ],
  ),
  TissueSalt(
    number: 5,
    remedy: 'Kali muriaticum',
    abbr: 'Kali mur.',
    tissue: 'Fibrin — the second stage of inflammation',
    indications: [
      'The second stage of inflammation, once discharge has turned white',
      'Thick, white or grey-white discharge from anywhere',
      'Blocked ear with a crackling noise on swallowing',
      'White-coated tongue',
      'Glandular swellings, chronic and firm',
      'Catarrh of the middle ear after a cold',
    ],
  ),
  TissueSalt(
    number: 6,
    remedy: 'Kali phosphoricum',
    abbr: 'Kali phos.',
    tissue: 'Nerve cells — the nutrient of the nervous system',
    indications: [
      'Nervous exhaustion after overwork, worry or long illness',
      'Mental fatigue where the patient cannot think or remember',
      'Sleeplessness from an overactive mind',
      'Headache of students and the overworked, better for gentle motion',
      'Nervous irritability with aversion to company',
      'Weakness with a foul-smelling discharge',
    ],
  ),
  TissueSalt(
    number: 7,
    remedy: 'Kali sulphuricum',
    abbr: 'Kali sulph.',
    tissue: 'Skin and internal linings — the carrier of oxygen to cells',
    indications: [
      'The third stage of inflammation, with yellow, slimy discharge',
      'Skin conditions with scaling and desquamation, psoriasis-like states',
      'Catarrh with yellow, stringy mucus',
      'Dandruff and scaling of the scalp',
      'Brittle nails and hair loss',
      'Worse in a warm, stuffy room, better in cool open air',
    ],
  ),
  TissueSalt(
    number: 8,
    remedy: 'Magnesia phosphorica',
    abbr: 'Mag phos.',
    tissue: 'Muscle and nerve — the antispasmodic',
    indications: [
      'Cramping, shooting, spasmodic pain, better for warmth and pressure',
      'Menstrual cramps relieved by heat and bending double',
      'Neuralgia, especially facial, better for warm applications',
      'Writer\'s cramp and muscle twitching',
      'Colic in infants',
      'Teeth sensitive to cold air and cold water',
    ],
  ),
  TissueSalt(
    number: 9,
    remedy: 'Natrum muriaticum',
    abbr: 'Nat mur.',
    tissue: 'Water distribution — where fluid is held and released',
    indications: [
      'Either too much or too little fluid: watery discharge, or dryness',
      'Watery coryza like clear egg white, with sneezing',
      'Dry, cracked lips and corners of the mouth',
      'Thirst with a craving for salt',
      'Watery blisters, cold sores',
      'Hay fever with streaming eyes and nose',
    ],
  ),
  TissueSalt(
    number: 10,
    remedy: 'Natrum phosphoricum',
    abbr: 'Nat phos.',
    tissue: 'Acid balance — the neutraliser',
    indications: [
      'Acidity: sour belching, heartburn, acid vomiting',
      'Creamy yellow coating at the back of the tongue',
      'Indigestion after fatty or rich food',
      'Rheumatic complaints attributed to excess acid',
      'Thread worms in children',
      'Jaundiced look to the whites of the eyes',
    ],
  ),
  TissueSalt(
    number: 11,
    remedy: 'Natrum sulphuricum',
    abbr: 'Nat sulph.',
    tissue: 'Removal of excess water — the eliminator',
    indications: [
      'Complaints worse in damp weather or a damp house',
      'Liver sluggishness with a bitter taste and green-yellow coating',
      'Bilious headache at the back of the head, worse in the morning',
      'Oedema and puffiness, water retention',
      'Asthma worse in wet weather',
      'Effects of a blow to the head, long after the injury',
    ],
  ),
  TissueSalt(
    number: 12,
    remedy: 'Silicea',
    abbr: 'Silica',
    tissue: 'Connective tissue, skin, nails and hair — the surgeon',
    indications: [
      'Suppuration that needs bringing to a head and expelling',
      'Boils, abscesses and whitlows that will not point',
      'Pushing out splinters and foreign bodies',
      'Slow-healing wounds, fistulae and sinuses',
      'Brittle nails with white spots, and thin, falling hair',
      'Offensive sweat of the feet',
    ],
  ),
];

/// How these are given.
///
/// Stated once rather than repeated on every salt, because the biochemic
/// system uses one schedule for all twelve, and differing figures per salt
/// would suggest a precision the system does not claim. Dosage is still the
/// prescriber's; this is the conventional starting point.
const String kTissueSaltDosing =
    'Usually 6X. Adults four tablets, children two, dissolved in the mouth '
    'away from food. Three or four times a day in a chronic case; every half '
    'hour to two hours in an acute one, reducing as it eases. Salts are '
    'commonly combined, and the numbers are taken together rather than being '
    'alternated.';

/// The salt with this number, or null outside 1 to 12.
TissueSalt? tissueSaltByNumber(int n) {
  for (final s in kTissueSalts) {
    if (s.number == n) return s;
  }
  return null;
}

/// Salts whose name, abbreviation, tissue or indications match [query].
///
/// Matching on indication as well as name is the point: the system is
/// prescribed by looking up a symptom, so "cramp" has to find Mag phos.
List<TissueSalt> searchTissueSalts(String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return kTissueSalts;
  // A bare number is how clinics and labels refer to these.
  final n = int.tryParse(q);
  if (n != null) {
    final hit = tissueSaltByNumber(n);
    return hit == null ? const [] : [hit];
  }
  return [
    for (final s in kTissueSalts)
      if (s.remedy.toLowerCase().contains(q) ||
          s.abbr
              .toLowerCase()
              .replaceAll('.', '')
              .contains(q.replaceAll('.', '')) ||
          s.tissue.toLowerCase().contains(q) ||
          s.indications.any((i) => i.toLowerCase().contains(q)))
        s,
  ];
}
