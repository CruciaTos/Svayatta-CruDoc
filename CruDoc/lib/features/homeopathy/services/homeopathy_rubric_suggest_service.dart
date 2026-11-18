import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/core/services/gemini_json_client.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/data/repertory/repertory_registry.dart';

/// One rubric the AI proposes, with the words from the case that led to it.
class RubricSuggestion {
  const RubricSuggestion({required this.rubricId, required this.why});

  final String rubricId;
  final String why;
}

/// Matches the symptom text of a case to the bundled repertory rubrics.
///
/// It goes through the same path as the other homeopathy AI features:
/// [GeminiJsonClient] (consent check, Gemini key or Firebase AI Logic,
/// usage metering). Only symptom text and the bundled "id | path" list are
/// sent: never a name, phone or e-mail. The model may only pick ids from the
/// list; anything else it returns is thrown away, so it cannot invent a
/// rubric.
class HomeopathyRubricSuggestService {
  HomeopathyRubricSuggestService({GeminiJsonClient? client})
    : _client = client ?? GeminiJsonClient();

  final GeminiJsonClient _client;

  static const maxSuggestions = 15;
  static const _maxCaseChars = 6000;
  static const _maxWhyChars = 160;
  static const _timeout = Duration(seconds: 45);

  @visibleForTesting
  static final Schema responseSchema = Schema.object(
    properties: {
      'suggestions': Schema.array(
        items: Schema.object(
          properties: {
            'rubricId': Schema.string(
              description: 'The id of one rubric from the list.',
            ),
            'why': Schema.string(
              description:
                  'A short exact quote from the case text that supports it.',
            ),
          },
          propertyOrdering: const ['rubricId', 'why'],
        ),
      ),
    },
  );

  @visibleForTesting
  static const systemPrompt = '''
You help a homeopathic physician choose repertory rubrics for a case.
You get (1) the symptom text of a case and (2) a numbered list of rubrics,
one per line as "id | path".

RULES:
1. Return only rubrics from the list, using the id exactly as written.
   Never invent a rubric and never change an id.
2. Choose a rubric only when the case text clearly states that symptom.
   Do not infer, guess or add what is merely typical. Fewer, well-supported
   rubrics are better than many. Return at most 15.
3. For each, "why" is a short exact quote (at most 15 words) copied from the
   case text. If you cannot quote the text, leave the rubric out.
4. Do not suggest remedies. Do not give advice. Do not diagnose.
5. If nothing in the list fits, return an empty list.
6. Respond ONLY with a JSON object: {"suggestions": [{"rubricId": "...",
   "why": "..."}]}.
''';

  /// Rubrics for [caseText] (already free of identifiers; see [caseText]).
  /// Throws what [GeminiJsonClient] throws: `AiConsentRequired` when AI is
  /// off, [FormatException] for an unreadable reply, plus network, timeout
  /// and Gemini errors.
  Future<List<RubricSuggestion>> suggest(
    String caseText, {
    Repertory? repertory,
  }) async {
    final rep = repertory ?? Repertory.instance;
    final text = caseText.trim();
    if (text.isEmpty) return const [];
    final list = rep.rubrics.map((r) => '${r.id} | ${r.path}').join('\n');
    final parsed = await _client.generateJson(
      systemPrompt: systemPrompt,
      prompt: 'CASE TEXT:\n"""\n$text\n"""\n\nRUBRICS:\n$list',
      schema: responseSchema,
      maxOutputTokens: 2048,
      timeout: _timeout,
      quick: true,
      feature: 'homeopathy_repertory',
    );
    return validate(parsed, rep);
  }

  /// Keeps only ids that exist in [rep], once each, at most
  /// [maxSuggestions]. Never throws.
  @visibleForTesting
  static List<RubricSuggestion> validate(
    Map<String, dynamic> parsed,
    Repertory rep,
  ) {
    final raw = parsed['suggestions'];
    if (raw is! List) return const [];
    final seen = <String>{};
    final out = <RubricSuggestion>[];
    for (final e in raw) {
      if (e is! Map) continue;
      final id = e['rubricId'];
      if (id is! String) continue;
      final clean = id.trim();
      if (rep.byId(clean) == null || !seen.add(clean)) continue;
      var why = (e['why'] is String ? e['why'] as String : '').trim();
      if (why.length > _maxWhyChars) {
        why = '${why.substring(0, _maxWhyChars).trimRight()}...';
      }
      out.add(RubricSuggestion(rubricId: clean, why: why));
      if (out.length >= maxSuggestions) break;
    }
    return out;
  }

  /// The symptom text of [sheet] (complaint, modalities, generals, mind,
  /// sleep, peculiar and a few physical fields) plus the doctor's [extra]
  /// words, with the patient's name ([names]) and any phone number or e-mail
  /// removed. Family, relationship and history fields are left out because
  /// they tend to carry other people's names.
  static String caseText(
    HomeopathyCaseSheet? sheet, {
    String extra = '',
    List<String> names = const [],
  }) {
    final lines = <String>[];
    void add(String label, String? value) {
      final v = value?.trim() ?? '';
      if (v.isNotEmpty) lines.add('$label: $v');
    }

    void addList(String label, List<String> values) {
      final v = values.where((s) => s.trim().isNotEmpty).join(', ');
      add(label, v);
    }

    if (sheet != null) {
      final cc = sheet.chiefComplaint;
      add('Complaint', cc.complaint);
      add('Location', cc.location);
      add('Sensation', cc.sensationDescription);
      add('Progression', cc.progression);
      add('Triggering causes', cc.triggeringCauses);
      add('Associated symptoms', cc.associatedSymptoms);

      final m = sheet.modalities;
      add('Worse from', m.aggravatingFactors);
      add('Better from', m.amelioratingFactors);
      add('Time pattern', m.timePatterns);
      add('Position', m.positionModalities);
      add('Motion', m.motionModalities);
      add('Rest', m.restModalities);
      add('Temperature and weather', m.temperatureWeather);
      add('Food and drink', m.foodDrinkModalities);
      add('Other triggers', m.otherTriggers);

      final g = sheet.generalSymptoms;
      if (g.thermalState != HomeopathyThermalState.unspecified) {
        add('Thermal state', g.thermalState.label);
      }
      add('Appetite', g.appetite);
      add('Thirst', g.thirst);
      add('Thirst style', g.thirstStyle);
      add('Hunger time', g.hungerTime);
      addList('Desires', g.cravingsDesires);
      addList('Aversions', g.aversionsDislikes);
      add('Perspiration', g.perspiration);
      add('Perspiration location', g.perspirationLocation);
      add('Perspiration odour', g.perspirationOdour);
      add('Stools', g.stools);
      add('Urine', g.urine);
      add('Energy', g.energyWeakness);

      final mind = sheet.mentalEmotional;
      add('Disposition', mind.disposition);
      addList('Fears', mind.fears);
      add('Fear details', mind.fearDetails);
      add('Anxiety triggers', mind.anxietyTriggers);
      add('Company or solitude', mind.companyVsSolitude);
      add('Consolation', mind.reactionToConsolation);
      add('Emotional cause', mind.emotionalAetiology);
      add('Dullness or restlessness', mind.dullnessVsRestlessness);
      add('Anger', mind.angerBodySymptoms);
      add('Sensitivity', mind.sensitivityDetails);
      add('Greatest grief', mind.greatestGrief);

      final s = sheet.dreamsSleep;
      add('Sleep', s.sleepQuality);
      add('Sleep disturbances', s.sleepDisturbances);
      add('Sleep posture', s.sleepPosture);
      add('Sleep behaviours', s.sleepBehaviors);
      add('Dreams', s.dreamCharacteristics);

      final p = sheet.physicalSymptoms;
      add('Head and vertigo', p.headVertigoSymptoms);
      add('Respiratory', p.respiratory);
      add('Cough', p.coughType);
      add('Digestive and stool', p.digestiveStoolDetails);
      add('Pain', p.painCharacteristics);
      add('Pain location', p.painLocation);
      add('Pain modalities', p.painModalities);

      final pec = sheet.peculiarSymptoms;
      add('Peculiar symptoms', pec.peculiarSRP);
      add('Keynotes', pec.keynoteObservations);
    }
    add('Doctor', extra);

    var text = scrub(lines.join('\n'), names);
    if (text.length > _maxCaseChars) {
      text = text.substring(0, _maxCaseChars);
    }
    return text;
  }

  /// Removes each word of [names] (case-insensitive, whole words), e-mail
  /// addresses and runs of 7 or more digits.
  @visibleForTesting
  static String scrub(String text, List<String> names) {
    var out = text;
    final words = <String>{
      for (final n in names)
        for (final w in n.split(RegExp(r'\s+')))
          if (w.trim().length >= 2) w.trim(),
    };
    for (final w in words) {
      out = out.replaceAll(
        RegExp('\\b${RegExp.escape(w)}\\b', caseSensitive: false),
        '[patient]',
      );
    }
    out = out.replaceAll(RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+'), '[email]');
    out = out.replaceAll(RegExp(r'\+?\d[\d\s-]{5,}\d'), '[number]');
    return out;
  }
}
