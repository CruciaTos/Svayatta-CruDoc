import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_ai/firebase_ai.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';

/// Service that leverages Gemini 2.0 Flash to extract structured homeopathic case
/// data (Chief complaint, Modalities, Generals, Physicals, Mind, Totality, Remedy)
/// from clinical speech or consultation transcripts.
class HomeopathyVoiceScribeService {
  HomeopathyVoiceScribeService._();
  static final instance = HomeopathyVoiceScribeService._();

  static const String _model = 'gemini-2.0-flash';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// Resolves optional developer Gemini key via explicit --dart-define.
  /// NOTE: Firebase client key is NEVER used as a fallback to prevent secret misuse.
  String get _apiKey {
    const envKey = String.fromEnvironment('GEMINI_API_KEY');
    return envKey;
  }

  /// System prompt instructing Gemini on homeopathic case synthesis
  static const String _systemPrompt = '''
You are an expert Homeopathic Clinical Scribe assistant.
Your task is to analyze a doctor's spoken case notes or patient consultation transcript, and extract the clinical details into structured JSON matching a Homeopathy Case Sheet.

CRITICAL INSTRUCTIONS:
1. ONLY extract information that was explicitly mentioned or clearly described in the narrative.
2. If a field was not mentioned in the recording, leave it as an empty string "" or empty array [].
3. For thermalState, value MUST be one of: "chilly", "hot", "ambithermal", or "unspecified".
4. For caseType, value MUST be one of: "chronic" or "acute".
5. For cravingsDesires and fears, map mentioned items to simple descriptive strings.
6. For reactionToConsolation, identify if patient is aggravated, ameliorated (soothed), or indifferent.
7. Return ONLY a valid, raw JSON object with NO markdown formatting, NO backticks (```json), and NO extra explanations.

JSON SCHEMA STRUCTURE:
{
  "overview": {
    "caseType": "acute" or "chronic",
    "chiefProblem": "string",
    "consultationReason": "string",
    "referralSource": "string",
    "priorHomeopathyExperience": "string",
    "patientPerceivedCause": "string"
  },
  "chiefComplaint": {
    "complaint": "string",
    "location": "string",
    "sensationDescription": "string",
    "onset": "string",
    "duration": "string",
    "frequency": "string",
    "progression": "string",
    "triggeringCauses": "string",
    "associatedSymptoms": "string"
  },
  "modalities": {
    "aggravatingFactors": "string",
    "amelioratingFactors": "string",
    "timePatterns": "string",
    "positionModalities": "string",
    "motionModalities": "string",
    "temperatureWeather": "string",
    "foodDrinkModalities": "string",
    "otherTriggers": "string"
  },
  "caseSheetCategory": "general" | "children" | "femaleEndocrine" | "acute",
  "generalSymptoms": {
    "thermalState": "chilly" | "hot" | "ambithermal" | "unspecified",
    "appetite": "string",
    "thirst": "string",
    "thirstStyle": "string",
    "hungerTime": "string",
    "hungerReaction": "string",
    "eatingSpeed": "string",
    "thirstTime": "string",
    "tasteChanges": "string",
    "cravingsDesires": ["string"],
    "aversionsDislikes": ["string"],
    "perspiration": "string",
    "perspirationLocation": "string",
    "perspirationOdour": "string",
    "stools": "string",
    "urine": "string",
    "skinState": "string",
    "energyWeakness": "string"
  },
  "physicalSymptoms": {
    "rheumatologyJoints": "string",
    "faceEnt": "string",
    "headVertigoSymptoms": "string",
    "respiratory": "string",
    "coughType": "string",
    "sputumDetails": "string",
    "coughTasteInMouth": "string",
    "feverChillStage": "string",
    "feverHeatStage": "string",
    "feverSweatStage": "string",
    "feverPeriodicity": "string",
    "digestiveStoolDetails": "string",
    "cnsNervous": "string",
    "painCharacteristics": "string",
    "painLocation": "string",
    "painModalities": "string"
  },
  "mentalEmotional": {
    "disposition": "string",
    "fears": ["string"],
    "anxietyTriggers": "string",
    "companyVsSolitude": "string",
    "reactionToConsolation": "string",
    "emotionalAetiology": "string",
    "reactionToDisease": "string",
    "dullnessVsRestlessness": "string",
    "facialExpression": "string",
    "mentalShiftSinceIllness": "string",
    "familyDynamics": "string",
    "spouseRelationship": "string",
    "childrenRelationship": "string",
    "inlawsRelationship": "string",
    "colleaguesWorkStress": "string",
    "majorTensions": "string",
    "upsetWorryTriggers": "string",
    "fearDetails": "string",
    "introvertExtrovert": "string",
    "stressHistory": "string",
    "relationshipStress": "string",
    "stressCopingMethods": "string",
    "sensitivityDetails": "string",
    "fixedHabits": "string",
    "angerBodySymptoms": "string",
    "companyPreference": "string",
    "disorderSensitivity": "string",
    "greatestGrief": "string",
    "greatestJoys": "string",
    "deeplyLikedActivities": "string",
    "deeplyDislikedMatters": "string",
    "disagreeableMindAspects": "string",
    "lifeSituationPicture": "string"
  },
  "dreamsSleep": {
    "sleepQuality": "string",
    "sleepDisturbances": "string",
    "dreamCharacteristics": "string",
    "sleepPosture": "string",
    "sleepPositionRestrictions": "string",
    "sleepBehaviors": "string",
    "childhoodDreams": "string"
  },
  "childhoodHistory": {
    "childhoodNature": "string",
    "childhoodHabits": "string",
    "childhoodFears": "string",
    "childhoodDreams": "string",
    "childhoodRelationships": "string",
    "childhoodSensitivities": "string"
  },
  "childrenCaseSheet": {
    "coldOrHeatSensitive": "string",
    "behaviorWhenUpset": "string",
    "whatMakesHappy": "string",
    "schoolBehavior": "string",
    "graspingIntelligenceScore": "number 1-10",
    "childTypeDescription": "string",
    "vaccinationHistory": "string",
    "favoriteSport": "string",
    "attitudeToParents": "string",
    "pastMedicalHistory": "string",
    "maturityLevel": "string",
    "familyProblemsReaction": "string",
    "introvertExtrovert": "string",
    "independenceLevel": "string",
    "dailyWaterIntake": "string",
    "birthComplications": "string",
    "motherPregnancyHistory": "string",
    "motherMedicalHistory": "string",
    "familyHealthHereditary": "string",
    "walkingTeethingAge": "string",
    "abnormalBehaviors": "string",
    "childFears": "string",
    "sleepingHabits": "string",
    "abnormalCravings": "string",
    "wormsProblems": "string",
    "headNoseThroat": "string",
    "coughRespiration": "string",
    "stomachAppetite": "string",
    "stoolUrinary": "string",
    "sexualAwareness": "string",
    "additionalChildInfo": "string"
  },
  "femaleEndocrine": {
    "medicalDiagnosis": "string",
    "howAndWhenStarted": "string",
    "physiologicalCauseTrigger": "string",
    "emotionalTriggers": "string",
    "diseaseManifestationLocation": "string",
    "otherOrgansInvolved": "string",
    "goitreDetails": "string",
    "glandsProblems": "string",
    "skinSymptoms": "string",
    "cardiacCirculatorySymptoms": "string",
    "stagesOfLifeChildhood": "string",
    "stagesOfLifePuberty": "string",
    "stagesOfLifePregnancy": "string",
    "stagesOfLifePostPartum": "string",
    "stagesOfLifeMenopause": "string",
    "physicalWeakness": "string"
  },
  "acuteSheet": {
    "howKnewAboutUs": "string",
    "priorHomeopathyUse": "string",
    "causeOfComplaint": "string",
    "otherProblems": "string",
    "mentalConditionDuringSuffering": "string",
    "waterRequirement": "string",
    "sweatDetails": "string",
    "postureModalities": "string",
    "sleepStoolUrination": "string",
    "overallHealthHistory": "string",
    "feverDetails": "string",
    "specialUncommonSymptoms": "string",
    "coughRespirationDetails": "string",
    "additionalCoughInfo": "string",
    "looseDryCough": "string",
    "diarrheaDysenteryConstipation": "string",
    "bodyPains": "string",
    "additionalInfo": "string"
  },
  "prescriptionNotes": {
    "prescribedRemedy": "string",
    "potency": "string",
    "repetitionScale": "string",
    "totalityOfSymptoms": "string",
    "differentialRemedies": "string",
    "repertorizationNotes": "string",
    "miasmaticTendency": "string",
    "adviceDiet": "string"
  },
  "followUp": {
    "responseRating": "string",
    "heringsLawDirection": "string",
    "clinicalChangesObserved": "string",
    "nextPrescriptionPlan": "string",
    "followUpNotes": "string"
  }
}
''';

  /// Parses a spoken consultation or dictation transcript into a structured
  /// partial [HomeopathyCaseSheet].
  Future<HomeopathyCaseSheet> extractFromTranscript(
    String transcript, {
    required HomeopathyCaseSheet existingSheet,
  }) async {
    if (transcript.trim().isEmpty) return existingSheet;

    final prompt = 'TRANSCRIPT TO PARSE:\n"""\n$transcript\n"""';

    String rawJsonResponse = '';

    // Attempt 1: Firebase AI SDK
    try {
      final model = FirebaseAI.googleAI().generativeModel(
        model: _model,
        systemInstruction: Content.text(_systemPrompt),
      );

      final response = await model.generateContent([
        Content.text(prompt),
      ]).timeout(const Duration(seconds: 15));

      rawJsonResponse = response.text?.trim() ?? '';
    } catch (e) {
      debugPrint('[HomeopathyVoiceScribeService] Firebase AI failed, trying REST: $e');
    }

    // Attempt 2: Production Secure Route: Firebase Cloud Function (Server-Side Secret Management)
    if (rawJsonResponse.isEmpty) {
      try {
        final callable = FirebaseFunctions.instanceFor(region: 'asia-south1')
            .httpsCallable('extractHomeopathyCaseSheet');
        final result = await callable.call({
          'transcript': transcript,
        }).timeout(const Duration(seconds: 15));

        final data = result.data;
        if (data is Map) {
          if (data['caseSheet'] is Map) {
            rawJsonResponse = jsonEncode(data['caseSheet']);
          } else if (data['rawResponse'] is String) {
            rawJsonResponse = data['rawResponse'] as String;
          }
        }
      } catch (e) {
        debugPrint('[HomeopathyVoiceScribeService] Cloud Function note: $e');
      }
    }

    // Attempt 3: Optional Direct REST Fallback (only if explicit developer key provided via --dart-define)
    if (rawJsonResponse.isEmpty) {
      try {
        final apiKey = _apiKey;
        if (apiKey.isNotEmpty) {
          final url = Uri.parse('$_baseUrl/$_model:generateContent?key=$apiKey');
          final response = await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': _systemPrompt}
                ]
              },
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': prompt}
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.1,
                'maxOutputTokens': 2048,
                'responseMimeType': 'application/json',
              },
            }),
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            final body = jsonDecode(response.body) as Map<String, dynamic>;
            final candidates = body['candidates'] as List<dynamic>?;
            if (candidates != null && candidates.isNotEmpty) {
              final content = candidates[0]['content'] as Map<String, dynamic>?;
              final parts = content?['parts'] as List<dynamic>?;
              if (parts != null && parts.isNotEmpty) {
                rawJsonResponse = parts[0]['text'] as String? ?? '';
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[HomeopathyVoiceScribeService] REST fallback failed: $e');
      }
    }

    if (rawJsonResponse.isEmpty) {
      return existingSheet;
    }

    return parseJsonIntoSheet(rawJsonResponse, existingSheet: existingSheet);
  }

  /// Parses JSON output from Gemini and merges it into [existingSheet].
  HomeopathyCaseSheet parseJsonIntoSheet(
    String rawJson, {
    required HomeopathyCaseSheet existingSheet,
  }) {
    try {
      var cleaned = rawJson.trim();
      if (cleaned.startsWith('```json')) {
        cleaned = cleaned.substring(7);
      }
      if (cleaned.startsWith('```')) {
        cleaned = cleaned.substring(3);
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
      cleaned = cleaned.trim();

      final data = jsonDecode(cleaned) as Map<String, dynamic>;

      // Overview
      final overviewData = data['overview'] as Map<String, dynamic>? ?? {};
      final parsedCaseType = overviewData['caseType'] != null
          ? HomeopathyCaseType.fromString(overviewData['caseType'].toString())
          : existingSheet.overview.caseType;

      final updatedOverview = existingSheet.overview.copyWith(
        caseType: parsedCaseType,
        chiefProblem: _mergeString(
            existingSheet.overview.chiefProblem, overviewData['chiefProblem']),
        consultationReason: _mergeString(
            existingSheet.overview.consultationReason,
            overviewData['consultationReason']),
        referralSource: _mergeString(existingSheet.overview.referralSource,
            overviewData['referralSource']),
        priorHomeopathyExperience: _mergeString(
            existingSheet.overview.priorHomeopathyExperience,
            overviewData['priorHomeopathyExperience']),
        patientPerceivedCause: _mergeString(
            existingSheet.overview.patientPerceivedCause,
            overviewData['patientPerceivedCause']),
      );

      // Chief Complaint
      final ccData = data['chiefComplaint'] as Map<String, dynamic>? ?? {};
      final updatedCC = existingSheet.chiefComplaint.copyWith(
        complaint: _mergeString(
            existingSheet.chiefComplaint.complaint, ccData['complaint']),
        location: _mergeString(
            existingSheet.chiefComplaint.location, ccData['location']),
        sensationDescription: _mergeString(
            existingSheet.chiefComplaint.sensationDescription,
            ccData['sensationDescription']),
        onset: _mergeString(existingSheet.chiefComplaint.onset, ccData['onset']),
        duration: _mergeString(
            existingSheet.chiefComplaint.duration, ccData['duration']),
        frequency: _mergeString(
            existingSheet.chiefComplaint.frequency, ccData['frequency']),
        progression: _mergeString(
            existingSheet.chiefComplaint.progression, ccData['progression']),
        triggeringCauses: _mergeString(
            existingSheet.chiefComplaint.triggeringCauses,
            ccData['triggeringCauses']),
        associatedSymptoms: _mergeString(
            existingSheet.chiefComplaint.associatedSymptoms,
            ccData['associatedSymptoms']),
      );

      // Modalities
      final modData = data['modalities'] as Map<String, dynamic>? ?? {};
      final updatedMod = existingSheet.modalities.copyWith(
        aggravatingFactors: _mergeString(
            existingSheet.modalities.aggravatingFactors,
            modData['aggravatingFactors']),
        amelioratingFactors: _mergeString(
            existingSheet.modalities.amelioratingFactors,
            modData['amelioratingFactors']),
        timePatterns: _mergeString(
            existingSheet.modalities.timePatterns, modData['timePatterns']),
        positionModalities: _mergeString(
            existingSheet.modalities.positionModalities,
            modData['positionModalities']),
        motionModalities: _mergeString(
            existingSheet.modalities.motionModalities,
            modData['motionModalities']),
        temperatureWeather: _mergeString(
            existingSheet.modalities.temperatureWeather,
            modData['temperatureWeather']),
        foodDrinkModalities: _mergeString(
            existingSheet.modalities.foodDrinkModalities,
            modData['foodDrinkModalities']),
        otherTriggers: _mergeString(
            existingSheet.modalities.otherTriggers, modData['otherTriggers']),
      );

      // Generals
      final genData = data['generalSymptoms'] as Map<String, dynamic>? ?? {};
      final parsedThermal = genData['thermalState'] != null
          ? HomeopathyThermalState.fromString(
              genData['thermalState'].toString())
          : existingSheet.generalSymptoms.thermalState;

      final updatedGen = existingSheet.generalSymptoms.copyWith(
        thermalState: parsedThermal != HomeopathyThermalState.unspecified
            ? parsedThermal
            : existingSheet.generalSymptoms.thermalState,
        appetite: _mergeString(
            existingSheet.generalSymptoms.appetite, genData['appetite']),
        thirst: _mergeString(
            existingSheet.generalSymptoms.thirst, genData['thirst']),
        thirstStyle: _mergeString(
            existingSheet.generalSymptoms.thirstStyle, genData['thirstStyle']),
        hungerTime: _mergeString(
            existingSheet.generalSymptoms.hungerTime, genData['hungerTime']),
        hungerReaction: _mergeString(
            existingSheet.generalSymptoms.hungerReaction,
            genData['hungerReaction']),
        eatingSpeed: _mergeString(
            existingSheet.generalSymptoms.eatingSpeed, genData['eatingSpeed']),
        thirstTime: _mergeString(
            existingSheet.generalSymptoms.thirstTime, genData['thirstTime']),
        tasteChanges: _mergeString(
            existingSheet.generalSymptoms.tasteChanges, genData['tasteChanges']),
        cravingsDesires: _mergeList(
            existingSheet.generalSymptoms.cravingsDesires,
            genData['cravingsDesires']),
        aversionsDislikes: _mergeList(
            existingSheet.generalSymptoms.aversionsDislikes,
            genData['aversionsDislikes']),
        perspiration: _mergeString(
            existingSheet.generalSymptoms.perspiration, genData['perspiration']),
        perspirationLocation: _mergeString(
            existingSheet.generalSymptoms.perspirationLocation,
            genData['perspirationLocation']),
        perspirationOdour: _mergeString(
            existingSheet.generalSymptoms.perspirationOdour,
            genData['perspirationOdour']),
        stools: _mergeString(
            existingSheet.generalSymptoms.stools, genData['stools']),
        urine: _mergeString(
            existingSheet.generalSymptoms.urine, genData['urine']),
        skinState: _mergeString(
            existingSheet.generalSymptoms.skinState, genData['skinState']),
        energyWeakness: _mergeString(
            existingSheet.generalSymptoms.energyWeakness,
            genData['energyWeakness']),
      );

      // Physicals
      final physData = data['physicalSymptoms'] as Map<String, dynamic>? ?? {};
      final updatedPhys = existingSheet.physicalSymptoms.copyWith(
        rheumatologyJoints: _mergeString(
            existingSheet.physicalSymptoms.rheumatologyJoints,
            physData['rheumatologyJoints']),
        faceEnt: _mergeString(
            existingSheet.physicalSymptoms.faceEnt, physData['faceEnt']),
        headVertigoSymptoms: _mergeString(
            existingSheet.physicalSymptoms.headVertigoSymptoms,
            physData['headVertigoSymptoms']),
        respiratory: _mergeString(
            existingSheet.physicalSymptoms.respiratory, physData['respiratory']),
        coughType: _mergeString(
            existingSheet.physicalSymptoms.coughType, physData['coughType']),
        sputumDetails: _mergeString(
            existingSheet.physicalSymptoms.sputumDetails,
            physData['sputumDetails']),
        coughTasteInMouth: _mergeString(
            existingSheet.physicalSymptoms.coughTasteInMouth,
            physData['coughTasteInMouth']),
        feverChillStage: _mergeString(
            existingSheet.physicalSymptoms.feverChillStage,
            physData['feverChillStage']),
        feverHeatStage: _mergeString(
            existingSheet.physicalSymptoms.feverHeatStage,
            physData['feverHeatStage']),
        feverSweatStage: _mergeString(
            existingSheet.physicalSymptoms.feverSweatStage,
            physData['feverSweatStage']),
        feverPeriodicity: _mergeString(
            existingSheet.physicalSymptoms.feverPeriodicity,
            physData['feverPeriodicity']),
        digestiveStoolDetails: _mergeString(
            existingSheet.physicalSymptoms.digestiveStoolDetails,
            physData['digestiveStoolDetails']),
        cnsNervous: _mergeString(
            existingSheet.physicalSymptoms.cnsNervous, physData['cnsNervous']),
        painCharacteristics: _mergeString(
            existingSheet.physicalSymptoms.painCharacteristics,
            physData['painCharacteristics']),
        painLocation: _mergeString(
            existingSheet.physicalSymptoms.painLocation,
            physData['painLocation']),
        painModalities: _mergeString(
            existingSheet.physicalSymptoms.painModalities,
            physData['painModalities']),
      );

      // Mental & Emotional
      final mindData = data['mentalEmotional'] as Map<String, dynamic>? ?? {};
      final updatedMind = existingSheet.mentalEmotional.copyWith(
        disposition: _mergeString(
            existingSheet.mentalEmotional.disposition, mindData['disposition']),
        fears: _mergeList(
            existingSheet.mentalEmotional.fears, mindData['fears']),
        anxietyTriggers: _mergeString(
            existingSheet.mentalEmotional.anxietyTriggers,
            mindData['anxietyTriggers']),
        companyVsSolitude: _mergeString(
            existingSheet.mentalEmotional.companyVsSolitude,
            mindData['companyVsSolitude']),
        reactionToConsolation: _mergeString(
            existingSheet.mentalEmotional.reactionToConsolation,
            mindData['reactionToConsolation']),
        emotionalAetiology: _mergeString(
            existingSheet.mentalEmotional.emotionalAetiology,
            mindData['emotionalAetiology']),
        reactionToDisease: _mergeString(
            existingSheet.mentalEmotional.reactionToDisease,
            mindData['reactionToDisease']),
        dullnessVsRestlessness: _mergeString(
            existingSheet.mentalEmotional.dullnessVsRestlessness,
            mindData['dullnessVsRestlessness']),
        facialExpression: _mergeString(
            existingSheet.mentalEmotional.facialExpression,
            mindData['facialExpression']),
        mentalShiftSinceIllness: _mergeString(
            existingSheet.mentalEmotional.mentalShiftSinceIllness,
            mindData['mentalShiftSinceIllness']),
        familyDynamics: _mergeString(
            existingSheet.mentalEmotional.familyDynamics,
            mindData['familyDynamics']),
        spouseRelationship: _mergeString(
            existingSheet.mentalEmotional.spouseRelationship,
            mindData['spouseRelationship']),
        childrenRelationship: _mergeString(
            existingSheet.mentalEmotional.childrenRelationship,
            mindData['childrenRelationship']),
        inlawsRelationship: _mergeString(
            existingSheet.mentalEmotional.inlawsRelationship,
            mindData['inlawsRelationship']),
        colleaguesWorkStress: _mergeString(
            existingSheet.mentalEmotional.colleaguesWorkStress,
            mindData['colleaguesWorkStress']),
        majorTensions: _mergeString(
            existingSheet.mentalEmotional.majorTensions,
            mindData['majorTensions']),
        upsetWorryTriggers: _mergeString(
            existingSheet.mentalEmotional.upsetWorryTriggers,
            mindData['upsetWorryTriggers']),
        fearDetails: _mergeString(
            existingSheet.mentalEmotional.fearDetails, mindData['fearDetails']),
        introvertExtrovert: _mergeString(
            existingSheet.mentalEmotional.introvertExtrovert,
            mindData['introvertExtrovert']),
        stressHistory: _mergeString(
            existingSheet.mentalEmotional.stressHistory,
            mindData['stressHistory']),
        stressCopingMethods: _mergeString(
            existingSheet.mentalEmotional.stressCopingMethods,
            mindData['stressCopingMethods']),
        sensitivityDetails: _mergeString(
            existingSheet.mentalEmotional.sensitivityDetails,
            mindData['sensitivityDetails']),
        fixedHabits: _mergeString(
            existingSheet.mentalEmotional.fixedHabits, mindData['fixedHabits']),
        angerBodySymptoms: _mergeString(
            existingSheet.mentalEmotional.angerBodySymptoms,
            mindData['angerBodySymptoms']),
        disorderSensitivity: _mergeString(
            existingSheet.mentalEmotional.disorderSensitivity,
            mindData['disorderSensitivity']),
        greatestGrief: _mergeString(
            existingSheet.mentalEmotional.greatestGrief,
            mindData['greatestGrief']),
        greatestJoys: _mergeString(
            existingSheet.mentalEmotional.greatestJoys,
            mindData['greatestJoys']),
        deeplyLikedActivities: _mergeString(
            existingSheet.mentalEmotional.deeplyLikedActivities,
            mindData['deeplyLikedActivities']),
        deeplyDislikedMatters: _mergeString(
            existingSheet.mentalEmotional.deeplyDislikedMatters,
            mindData['deeplyDislikedMatters']),
        disagreeableMindAspects: _mergeString(
            existingSheet.mentalEmotional.disagreeableMindAspects,
            mindData['disagreeableMindAspects']),
        lifeSituationPicture: _mergeString(
            existingSheet.mentalEmotional.lifeSituationPicture,
            mindData['lifeSituationPicture']),
      );

      // Dreams & Sleep
      final sleepData = data['dreamsSleep'] as Map<String, dynamic>? ?? {};
      final updatedSleep = existingSheet.dreamsSleep.copyWith(
        sleepQuality: _mergeString(
            existingSheet.dreamsSleep.sleepQuality, sleepData['sleepQuality']),
        sleepDisturbances: _mergeString(
            existingSheet.dreamsSleep.sleepDisturbances,
            sleepData['sleepDisturbances']),
        dreamCharacteristics: _mergeString(
            existingSheet.dreamsSleep.dreamCharacteristics,
            sleepData['dreamCharacteristics']),
        sleepPosture: _mergeString(
            existingSheet.dreamsSleep.sleepPosture, sleepData['sleepPosture']),
        sleepPositionRestrictions: _mergeString(
            existingSheet.dreamsSleep.sleepPositionRestrictions,
            sleepData['sleepPositionRestrictions']),
        sleepBehaviors: _mergeString(
            existingSheet.dreamsSleep.sleepBehaviors,
            sleepData['sleepBehaviors']),
        childhoodDreams: _mergeString(
            existingSheet.dreamsSleep.childhoodDreams,
            sleepData['childhoodDreams']),
      );

      // Childhood History
      final childHistData =
          data['childhoodHistory'] as Map<String, dynamic>? ?? {};
      final updatedChildHist = existingSheet.childhoodHistory.copyWith(
        childhoodNature: _mergeString(
            existingSheet.childhoodHistory.childhoodNature,
            childHistData['childhoodNature']),
        childhoodHabits: _mergeString(
            existingSheet.childhoodHistory.childhoodHabits,
            childHistData['childhoodHabits']),
        childhoodFears: _mergeString(
            existingSheet.childhoodHistory.childhoodFears,
            childHistData['childhoodFears']),
        childhoodDreams: _mergeString(
            existingSheet.childhoodHistory.childhoodDreams,
            childHistData['childhoodDreams']),
        childhoodRelationships: _mergeString(
            existingSheet.childhoodHistory.childhoodRelationships,
            childHistData['childhoodRelationships']),
        childhoodSensitivities: _mergeString(
            existingSheet.childhoodHistory.childhoodSensitivities,
            childHistData['childhoodSensitivities']),
      );

      // Children Case Sheet
      final pediaData =
          data['childrenCaseSheet'] as Map<String, dynamic>? ?? {};
      final scoreVal =
          (pediaData['graspingIntelligenceScore'] as num?)?.toInt();
      final updatedPedia = existingSheet.childrenCaseSheet.copyWith(
        coldOrHeatSensitive: _mergeString(
            existingSheet.childrenCaseSheet.coldOrHeatSensitive,
            pediaData['coldOrHeatSensitive']),
        behaviorWhenUpset: _mergeString(
            existingSheet.childrenCaseSheet.behaviorWhenUpset,
            pediaData['behaviorWhenUpset']),
        whatMakesHappy: _mergeString(
            existingSheet.childrenCaseSheet.whatMakesHappy,
            pediaData['whatMakesHappy']),
        schoolBehavior: _mergeString(
            existingSheet.childrenCaseSheet.schoolBehavior,
            pediaData['schoolBehavior']),
        graspingIntelligenceScore: scoreVal ??
            existingSheet.childrenCaseSheet.graspingIntelligenceScore,
        childTypeDescription: _mergeString(
            existingSheet.childrenCaseSheet.childTypeDescription,
            pediaData['childTypeDescription']),
        vaccinationHistory: _mergeString(
            existingSheet.childrenCaseSheet.vaccinationHistory,
            pediaData['vaccinationHistory']),
        favoriteSportActivity: _mergeString(
            existingSheet.childrenCaseSheet.favoriteSportActivity,
            pediaData['favoriteSportActivity'] ?? pediaData['favoriteSport']),
        attitudeToParents: _mergeString(
            existingSheet.childrenCaseSheet.attitudeToParents,
            pediaData['attitudeToParents']),
        childMedicalHistory: _mergeString(
            existingSheet.childrenCaseSheet.childMedicalHistory,
            pediaData['childMedicalHistory'] ?? pediaData['pastMedicalHistory']),
        maturityLevel: _mergeString(
            existingSheet.childrenCaseSheet.maturityLevel,
            pediaData['maturityLevel']),
        familyProblemsReaction: _mergeString(
            existingSheet.childrenCaseSheet.familyProblemsReaction,
            pediaData['familyProblemsReaction']),
        childIntrovertExtrovert: _mergeString(
            existingSheet.childrenCaseSheet.childIntrovertExtrovert,
            pediaData['childIntrovertExtrovert'] ?? pediaData['introvertExtrovert']),
        independenceLevel: _mergeString(
            existingSheet.childrenCaseSheet.independenceLevel,
            pediaData['independenceLevel']),
        dailyWaterIntake: _mergeString(
            existingSheet.childrenCaseSheet.dailyWaterIntake,
            pediaData['dailyWaterIntake']),
        birthComplications: _mergeString(
            existingSheet.childrenCaseSheet.birthComplications,
            pediaData['birthComplications']),
        motherPregnancyHistory: _mergeString(
            existingSheet.childrenCaseSheet.motherPregnancyHistory,
            pediaData['motherPregnancyHistory']),
        motherMedicalHistory: _mergeString(
            existingSheet.childrenCaseSheet.motherMedicalHistory,
            pediaData['motherMedicalHistory']),
        familyHealthHereditary: _mergeString(
            existingSheet.childrenCaseSheet.familyHealthHereditary,
            pediaData['familyHealthHereditary']),
        walkingTeethingAge: _mergeString(
            existingSheet.childrenCaseSheet.walkingTeethingAge,
            pediaData['walkingTeethingAge']),
        abnormalBehaviors: _mergeString(
            existingSheet.childrenCaseSheet.abnormalBehaviors,
            pediaData['abnormalBehaviors']),
        childFears: _mergeString(existingSheet.childrenCaseSheet.childFears,
            pediaData['childFears']),
        childSleepingHabits: _mergeString(
            existingSheet.childrenCaseSheet.childSleepingHabits,
            pediaData['childSleepingHabits'] ?? pediaData['sleepingHabits']),
        abnormalCravings: _mergeString(
            existingSheet.childrenCaseSheet.abnormalCravings,
            pediaData['abnormalCravings']),
        wormsProblems: _mergeString(
            existingSheet.childrenCaseSheet.wormsProblems,
            pediaData['wormsProblems']),
        headSymptoms: _mergeString(
            existingSheet.childrenCaseSheet.headSymptoms,
            pediaData['headSymptoms'] ?? pediaData['headNoseThroat']),
        coughAsthmaDetails: _mergeString(
            existingSheet.childrenCaseSheet.coughAsthmaDetails,
            pediaData['coughAsthmaDetails'] ?? pediaData['coughRespiration']),
        stomachSymptoms: _mergeString(
            existingSheet.childrenCaseSheet.stomachSymptoms,
            pediaData['stomachSymptoms'] ?? pediaData['stomachAppetite']),
        stoolRectumSymptoms: _mergeString(
            existingSheet.childrenCaseSheet.stoolRectumSymptoms,
            pediaData['stoolRectumSymptoms'] ?? pediaData['stoolUrinary']),
        sexualAwareness: _mergeString(
            existingSheet.childrenCaseSheet.sexualAwareness,
            pediaData['sexualAwareness']),
        additionalChildInfo: _mergeString(
            existingSheet.childrenCaseSheet.additionalChildInfo,
            pediaData['additionalChildInfo']),
      );

      // Female & Endocrine
      final femEndoData =
          data['femaleEndocrine'] as Map<String, dynamic>? ?? {};
      final updatedFemEndo = existingSheet.femaleEndocrine.copyWith(
        medicalDiagnosis: _mergeString(
            existingSheet.femaleEndocrine.medicalDiagnosis,
            femEndoData['medicalDiagnosis']),
        howAndWhenStarted: _mergeString(
            existingSheet.femaleEndocrine.howAndWhenStarted,
            femEndoData['howAndWhenStarted']),
        physiologicalCauseTrigger: _mergeString(
            existingSheet.femaleEndocrine.physiologicalCauseTrigger,
            femEndoData['physiologicalCauseTrigger']),
        emotionalTriggers: _mergeString(
            existingSheet.femaleEndocrine.emotionalTriggers,
            femEndoData['emotionalTriggers']),
        diseaseManifestationLocation: _mergeString(
            existingSheet.femaleEndocrine.diseaseManifestationLocation,
            femEndoData['diseaseManifestationLocation']),
        otherOrgansInvolved: _mergeString(
            existingSheet.femaleEndocrine.otherOrgansInvolved,
            femEndoData['otherOrgansInvolved']),
        goitreDetails: _mergeString(
            existingSheet.femaleEndocrine.goitreDetails,
            femEndoData['goitreDetails']),
        glandsProblems: _mergeString(
            existingSheet.femaleEndocrine.glandsProblems,
            femEndoData['glandsProblems']),
        skinSymptoms: _mergeString(
            existingSheet.femaleEndocrine.skinSymptoms,
            femEndoData['skinSymptoms']),
        cardiacCirculatorySymptoms: _mergeString(
            existingSheet.femaleEndocrine.cardiacCirculatorySymptoms,
            femEndoData['cardiacCirculatorySymptoms']),
        stagesOfLife: _mergeString(
            existingSheet.femaleEndocrine.stagesOfLife,
            femEndoData['stagesOfLife'] ??
                femEndoData['stagesOfLifeChildhood']),
        physicalWeakness: _mergeString(
            existingSheet.femaleEndocrine.physicalWeakness,
            femEndoData['physicalWeakness']),
      );

      // Acute Sheet
      final acuteData = data['acuteSheet'] as Map<String, dynamic>? ?? {};
      final updatedAcute = existingSheet.acuteSheet.copyWith(
        howKnewAboutUs: _mergeString(existingSheet.acuteSheet.howKnewAboutUs,
            acuteData['howKnewAboutUs']),
        priorHomeopathyUse: _mergeString(
            existingSheet.acuteSheet.priorHomeopathyUse,
            acuteData['priorHomeopathyUse']),
        causeOfComplaint: _mergeString(
            existingSheet.acuteSheet.causeOfComplaint,
            acuteData['causeOfComplaint']),
        otherProblems: _mergeString(
            existingSheet.acuteSheet.otherProblems, acuteData['otherProblems']),
        mentalConditionDuringSuffering: _mergeString(
            existingSheet.acuteSheet.mentalConditionDuringSuffering,
            acuteData['mentalConditionDuringSuffering']),
        waterRequirement: _mergeString(
            existingSheet.acuteSheet.waterRequirement,
            acuteData['waterRequirement']),
        sweatDetails: _mergeString(
            existingSheet.acuteSheet.sweatDetails, acuteData['sweatDetails']),
        postureModalities: _mergeString(
            existingSheet.acuteSheet.postureModalities,
            acuteData['postureModalities']),
        sleepStoolUrination: _mergeString(
            existingSheet.acuteSheet.sleepStoolUrination,
            acuteData['sleepStoolUrination']),
        overallHealthHistory: _mergeString(
            existingSheet.acuteSheet.overallHealthHistory,
            acuteData['overallHealthHistory']),
        acuteFeverDetails: _mergeString(
            existingSheet.acuteSheet.acuteFeverDetails,
            acuteData['acuteFeverDetails'] ?? acuteData['feverDetails']),
        specialUncommonSymptoms: _mergeString(
            existingSheet.acuteSheet.specialUncommonSymptoms,
            acuteData['specialUncommonSymptoms']),
        coughRespirationDetail: _mergeString(
            existingSheet.acuteSheet.coughRespirationDetail,
            acuteData['coughRespirationDetail'] ?? acuteData['coughRespirationDetails']),
        additionalCoughInfo: _mergeString(
            existingSheet.acuteSheet.additionalCoughInfo,
            acuteData['additionalCoughInfo']),
        looseDryCoughDetails: _mergeString(
            existingSheet.acuteSheet.looseDryCoughDetails,
            acuteData['looseDryCoughDetails'] ?? acuteData['looseDryCough']),
        diarrheaConstipationDetails: _mergeString(
            existingSheet.acuteSheet.diarrheaConstipationDetails,
            acuteData['diarrheaConstipationDetails'] ?? acuteData['diarrheaDysenteryConstipation']),
        bodyPainDetails: _mergeString(
            existingSheet.acuteSheet.bodyPainDetails,
            acuteData['bodyPainDetails'] ?? acuteData['bodyPains']),
        additionalInfo: _mergeString(
            existingSheet.acuteSheet.additionalInfo, acuteData['additionalInfo']),
      );

      // Prescription & Totality
      final rxData = data['prescriptionNotes'] as Map<String, dynamic>? ?? {};
      final updatedRx = existingSheet.prescriptionNotes.copyWith(
        prescribedRemedy: _mergeString(
            existingSheet.prescriptionNotes.prescribedRemedy,
            rxData['prescribedRemedy']),
        potency: _mergeString(
            existingSheet.prescriptionNotes.potency, rxData['potency']),
        repetitionScale: _mergeString(
            existingSheet.prescriptionNotes.repetitionScale,
            rxData['repetitionScale']),
        totalityOfSymptoms: _mergeString(
            existingSheet.prescriptionNotes.totalityOfSymptoms,
            rxData['totalityOfSymptoms']),
        differentialRemedies: _mergeString(
            existingSheet.prescriptionNotes.differentialRemedies,
            rxData['differentialRemedies']),
        repertorizationNotes: _mergeString(
            existingSheet.prescriptionNotes.repertorizationNotes,
            rxData['repertorizationNotes']),
        miasmaticTendency: _mergeString(
            existingSheet.prescriptionNotes.miasmaticTendency,
            rxData['miasmaticTendency']),
        adviceDiet: _mergeString(
            existingSheet.prescriptionNotes.adviceDiet, rxData['adviceDiet']),
      );

      // Follow-up
      final fuData = data['followUp'] as Map<String, dynamic>? ?? {};
      final updatedFu = existingSheet.followUp.copyWith(
        responseRating: _mergeString(
            existingSheet.followUp.responseRating, fuData['responseRating']),
        heringsLawDirection: _mergeString(
            existingSheet.followUp.heringsLawDirection,
            fuData['heringsLawDirection']),
        clinicalChangesObserved: _mergeString(
            existingSheet.followUp.clinicalChangesObserved,
            fuData['clinicalChangesObserved']),
        nextPrescriptionPlan: _mergeString(
            existingSheet.followUp.nextPrescriptionPlan,
            fuData['nextPrescriptionPlan']),
        followUpNotes: _mergeString(
            existingSheet.followUp.followUpNotes, fuData['followUpNotes']),
      );

      // Case Category
      final catStr = data['caseSheetCategory']?.toString();
      final parsedCategory = catStr != null && catStr.isNotEmpty
          ? HomeopathyCaseSheetCategory.fromString(catStr)
          : existingSheet.caseSheetCategory;

      return existingSheet.copyWith(
        caseSheetCategory: parsedCategory,
        overview: updatedOverview,
        chiefComplaint: updatedCC,
        modalities: updatedMod,
        generalSymptoms: updatedGen,
        physicalSymptoms: updatedPhys,
        mentalEmotional: updatedMind,
        dreamsSleep: updatedSleep,
        childhoodHistory: updatedChildHist,
        childrenCaseSheet: updatedPedia,
        femaleEndocrine: updatedFemEndo,
        acuteSheet: updatedAcute,
        prescriptionNotes: updatedRx,
        followUp: updatedFu,
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[HomeopathyVoiceScribeService] Error parsing JSON into sheet: $e');
      return existingSheet;
    }
  }

  String _mergeString(String existing, dynamic incoming) {
    if (incoming == null) return existing;
    final str = incoming.toString().trim();
    if (str.isEmpty) return existing;
    return str;
  }

  List<String> _mergeList(List<String> existing, dynamic incoming) {
    if (incoming == null) return existing;
    if (incoming is! List) return existing;
    final set = Set<String>.from(existing);
    for (final item in incoming) {
      final s = item?.toString().trim() ?? '';
      if (s.isNotEmpty) {
        set.add(s);
      }
    }
    return set.toList();
  }
}
