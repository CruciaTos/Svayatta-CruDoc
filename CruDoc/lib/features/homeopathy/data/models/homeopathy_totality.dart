import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';

/// Weight a physician gives a symptom when building the totality.
enum HomeoTier {
  common('Common'),
  characteristic('Characteristic'),
  mentalGeneral('Mental general'),
  physicalGeneral('Physical general'),
  particular('Particular');

  const HomeoTier(this.label);
  final String label;

  /// Order symptoms are listed in the copied totality.
  static const listOrder = [
    mentalGeneral,
    characteristic,
    physicalGeneral,
    particular,
    common,
  ];

  bool get inTotality => this == characteristic || this == mentalGeneral;

  static HomeoTier? fromName(String? n) {
    for (final t in values) {
      if (t.name == n) return t;
    }
    return null;
  }
}

/// Miasm tags a symptom (or the whole case) can carry.
const homeoMiasms = ['psoric', 'sycotic', 'syphilitic', 'tubercular', 'mixed'];

/// One symptom taken from the case sheet and the physician's marks on it.
class HomeoTotalityItem {
  const HomeoTotalityItem({
    required this.source,
    required this.text,
    this.tier,
    this.miasm = '',
    this.skip = false,
  });

  factory HomeoTotalityItem.fromJson(Map<String, dynamic> j) =>
      HomeoTotalityItem(
        source: j['source'] as String? ?? '',
        text: j['text'] as String? ?? '',
        tier: HomeoTier.fromName(j['tier'] as String?),
        miasm: j['miasm'] as String? ?? '',
        skip: j['skip'] == true,
      );

  final String source;
  final String text;
  final HomeoTier? tier;
  final String miasm;
  final bool skip;

  String get key => text.trim().toLowerCase();

  HomeoTotalityItem copyWith({
    HomeoTier? tier,
    bool clearTier = false,
    String? miasm,
    bool? skip,
  }) => HomeoTotalityItem(
    source: source,
    text: text,
    tier: clearTier ? null : (tier ?? this.tier),
    miasm: miasm ?? this.miasm,
    skip: skip ?? this.skip,
  );

  Map<String, dynamic> toJson() => {
    'source': source,
    'text': text,
    'tier': tier?.name ?? '',
    'miasm': miasm,
    'skip': skip,
  };
}

/// The saved totality of one patient (record kind `homeoTotality`).
class HomeoTotality {
  const HomeoTotality({
    this.items = const [],
    this.miasmCase = const [],
    this.record,
  });

  factory HomeoTotality.fromRecord(DentalRecord r) {
    final raw = r.data['items'];
    final mc = r.data['miasmCase'];
    return HomeoTotality(
      items: [
        if (raw is List)
          for (final e in raw)
            if (e is Map)
              HomeoTotalityItem.fromJson(Map<String, dynamic>.from(e)),
      ],
      miasmCase: [
        if (mc is List)
          for (final m in mc) m.toString(),
      ],
      record: r,
    );
  }

  final List<HomeoTotalityItem> items;
  final List<String> miasmCase;
  final DentalRecord? record;

  Iterable<HomeoTotalityItem> get active => items.where((i) => !i.skip);

  int get characteristicCount =>
      active.where((i) => i.tier == HomeoTier.characteristic).length;

  /// Dominant miasm from the symptom tags, else from the whole-case tags.
  ({String name, int count, int of})? get dominant =>
      dominantMiasm(items, miasmCase);

  Map<String, dynamic> toData() => {
    'items': [for (final i in items) i.toJson()],
    'miasmCase': miasmCase,
  };
}

({String name, int count, int of})? dominantMiasm(
  List<HomeoTotalityItem> items,
  List<String> miasmCase,
) {
  final counts = <String, int>{};
  for (final i in items) {
    if (!i.skip && i.miasm.isNotEmpty) {
      counts[i.miasm] = (counts[i.miasm] ?? 0) + 1;
    }
  }
  if (counts.isEmpty) {
    if (miasmCase.isEmpty) return null;
    return (name: miasmCase.join(' + '), count: 0, of: 0);
  }
  final total = counts.values.fold<int>(0, (a, b) => a + b);
  final best = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
  return (name: best.key, count: best.value, of: total);
}

/// "Dominant: psoric 4 of 9 tagged".
String dominantLine(({String name, int count, int of}) d) => d.of == 0
    ? 'Dominant: ${d.name} (whole case)'
    : 'Dominant: ${d.name} ${d.count} of ${d.of} tagged';

/// The ordered totality as plain text, one symptom per line, grouped by
/// tier (mental generals and characteristics first). Skipped symptoms and
/// untiered ones are left out.
String totalityText(List<HomeoTotalityItem> items) {
  final lines = <String>[];
  for (final t in HomeoTier.listOrder) {
    for (final i in items) {
      if (!i.skip && i.tier == t) lines.add('${t.label}: ${i.text}');
    }
  }
  return lines.join('\n');
}

/// Splits a free-text case-sheet field into single symptoms.
List<String> splitSymptoms(String raw) {
  final out = <String>[];
  for (final part in raw.split(RegExp(r'[\n;,]'))) {
    final t = part.replaceFirst(RegExp(r'^[\s\-*•]+'), '').trim();
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}

/// Reads the case sheet's text fields into untiered symptoms. Empty fields
/// are skipped; duplicates within the same section are dropped.
List<HomeoTotalityItem> symptomsFromCaseSheet(HomeopathyCaseSheet s) {
  final items = <HomeoTotalityItem>[];
  final seen = <String>{};

  void add(String section, String raw, {String prefix = ''}) {
    for (final part in splitSymptoms(raw)) {
      final text = prefix.isEmpty ? part : '$prefix: $part';
      if (seen.add('$section|${text.toLowerCase()}')) {
        items.add(HomeoTotalityItem(source: section, text: text));
      }
    }
  }

  void addList(String section, List<String> raw, {String prefix = ''}) {
    for (final e in raw) {
      add(section, e, prefix: prefix);
    }
  }

  final cc = s.chiefComplaint;
  const chief = 'Chief complaint';
  add(chief, cc.complaint);
  add(chief, cc.sensationDescription, prefix: 'Sensation');
  add(chief, cc.associatedSymptoms, prefix: 'Associated');

  final m = s.modalities;
  const mod = 'Modalities';
  add(mod, m.aggravatingFactors, prefix: 'Worse');
  add(mod, m.amelioratingFactors, prefix: 'Better');
  add(mod, m.timePatterns, prefix: 'Time');
  add(mod, m.positionModalities, prefix: 'Position');
  add(mod, m.motionModalities, prefix: 'Motion');
  add(mod, m.restModalities, prefix: 'Rest');
  add(mod, m.temperatureWeather, prefix: 'Weather');
  add(mod, m.foodDrinkModalities, prefix: 'Food and drink');

  final g = s.generalSymptoms;
  const gen = 'Generals';
  if (g.thermalState != HomeopathyThermalState.unspecified) {
    add(
      gen,
      g.thermalState.name[0].toUpperCase() + g.thermalState.name.substring(1),
    );
  }
  addList(gen, g.cravingsDesires, prefix: 'Craves');
  addList(gen, g.aversionsDislikes, prefix: 'Averse to');
  add(gen, g.thirst, prefix: 'Thirst');
  add(gen, g.thirstStyle, prefix: 'Thirst');
  add(gen, g.appetite, prefix: 'Appetite');
  add(gen, g.perspiration, prefix: 'Perspiration');

  final me = s.mentalEmotional;
  const mind = 'Mental and emotional';
  add(mind, me.disposition);
  addList(mind, me.fears, prefix: 'Fear');
  add(mind, me.fearDetails, prefix: 'Fear');
  add(mind, me.anxietyTriggers, prefix: 'Anxiety');
  add(mind, me.companyVsSolitude);
  add(mind, me.reactionToConsolation, prefix: 'Consolation');
  add(mind, me.emotionalAetiology, prefix: 'Ailments from');
  add(mind, me.greatestGrief, prefix: 'Grief');
  add(mind, me.fixedHabits);

  final p = s.peculiarSymptoms;
  const pec = 'Peculiar symptoms';
  add(pec, p.peculiarSRP);
  add(pec, p.keynoteObservations);

  final d = s.dreamsSleep;
  const sleep = 'Dreams and sleep';
  addList(sleep, d.recurringDreams, prefix: 'Dream');
  add(sleep, d.dreamCharacteristics, prefix: 'Dream');
  add(sleep, d.sleepPosture, prefix: 'Sleeps');
  add(sleep, d.sleepPositionRestrictions, prefix: 'Cannot sleep');
  add(sleep, d.sleepBehaviors);
  add(sleep, d.sleepDisturbances, prefix: 'Sleep');

  return items;
}

/// Builds the item list for a patient: the case sheet's current symptoms,
/// keeping the tier, miasm and leave-out of any symptom whose text is
/// unchanged from [saved].
List<HomeoTotalityItem> mergeTotality(
  List<HomeoTotalityItem> fresh,
  List<HomeoTotalityItem> saved,
) {
  final byKey = {for (final i in saved) '${i.source}|${i.key}': i};
  return [
    for (final f in fresh)
      if (byKey['${f.source}|${f.key}'] case final old?)
        HomeoTotalityItem(
          source: f.source,
          text: f.text,
          tier: old.tier,
          miasm: old.miasm,
          skip: old.skip,
        )
      else
        f,
  ];
}
