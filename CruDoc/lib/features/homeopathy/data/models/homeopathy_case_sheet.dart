import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_extended_sections.dart';
export 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_extended_sections.dart';

/// Thermal reaction state in Classical Homeopathy.
enum HomeopathyThermalState {
  chilly,
  hot,
  ambithermal,
  unspecified;

  static HomeopathyThermalState fromString(String? val) {
    if (val == null) return HomeopathyThermalState.unspecified;
    final lower = val.toLowerCase().trim();
    if (lower == 'chilly') return HomeopathyThermalState.chilly;
    if (lower == 'hot') return HomeopathyThermalState.hot;
    if (lower == 'ambithermal' || lower == 'both') return HomeopathyThermalState.ambithermal;
    return HomeopathyThermalState.unspecified;
  }

  String get label {
    switch (this) {
      case HomeopathyThermalState.chilly:
        return 'Chilly (Cannot tolerate cold)';
      case HomeopathyThermalState.hot:
        return 'Hot (Cannot tolerate warmth)';
      case HomeopathyThermalState.ambithermal:
        return 'Ambithermal (Sensitive to both)';
      case HomeopathyThermalState.unspecified:
        return 'Unspecified';
    }
  }
}

/// Case type: Acute or Chronic case taking.
enum HomeopathyCaseType {
  acute,
  chronic;

  static HomeopathyCaseType fromString(String? val) {
    if (val?.toLowerCase().trim() == 'acute') return HomeopathyCaseType.acute;
    return HomeopathyCaseType.chronic;
  }

  String get label => this == HomeopathyCaseType.acute ? 'Acute Case' : 'Chronic Case';
}

/// A. Case Overview & Onboarding
class HomeopathyCaseOverview {
  final HomeopathyCaseType caseType;
  final DateTime caseDate;
  final String chiefProblem;
  final String priority;
  final String consultationReason;
  final String referralSource;
  final String priorHomeopathyExperience;
  final String patientPerceivedCause;

  const HomeopathyCaseOverview({
    this.caseType = HomeopathyCaseType.chronic,
    required this.caseDate,
    this.chiefProblem = '',
    this.priority = 'normal',
    this.consultationReason = '',
    this.referralSource = '',
    this.priorHomeopathyExperience = '',
    this.patientPerceivedCause = '',
  });

  bool get isCompleted => chiefProblem.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'caseType': caseType.name,
        'caseDate': caseDate.millisecondsSinceEpoch,
        'chiefProblem': chiefProblem,
        'priority': priority,
        'consultationReason': consultationReason,
        'referralSource': referralSource,
        'priorHomeopathyExperience': priorHomeopathyExperience,
        'patientPerceivedCause': patientPerceivedCause,
      };

  factory HomeopathyCaseOverview.fromMap(Map<String, dynamic> map) =>
      HomeopathyCaseOverview(
        caseType: HomeopathyCaseType.fromString(map['caseType'] as String?),
        caseDate: map['caseDate'] != null
            ? DateTime.fromMillisecondsSinceEpoch((map['caseDate'] as num).toInt())
            : DateTime.now(),
        chiefProblem: map['chiefProblem'] as String? ?? '',
        priority: map['priority'] as String? ?? 'normal',
        consultationReason: map['consultationReason'] as String? ?? '',
        referralSource: map['referralSource'] as String? ?? '',
        priorHomeopathyExperience:
            map['priorHomeopathyExperience'] as String? ?? '',
        patientPerceivedCause: map['patientPerceivedCause'] as String? ?? '',
      );

  HomeopathyCaseOverview copyWith({
    HomeopathyCaseType? caseType,
    DateTime? caseDate,
    String? chiefProblem,
    String? priority,
    String? consultationReason,
    String? referralSource,
    String? priorHomeopathyExperience,
    String? patientPerceivedCause,
  }) =>
      HomeopathyCaseOverview(
        caseType: caseType ?? this.caseType,
        caseDate: caseDate ?? this.caseDate,
        chiefProblem: chiefProblem ?? this.chiefProblem,
        priority: priority ?? this.priority,
        consultationReason: consultationReason ?? this.consultationReason,
        referralSource: referralSource ?? this.referralSource,
        priorHomeopathyExperience:
            priorHomeopathyExperience ?? this.priorHomeopathyExperience,
        patientPerceivedCause:
            patientPerceivedCause ?? this.patientPerceivedCause,
      );
}

/// B. Chief Complaint
class HomeopathyChiefComplaint {
  final String complaint;
  final String location;
  final String sensationDescription;
  final String onset;
  final String duration;
  final String frequency;
  final String progression;
  final String triggeringCauses;
  final String associatedSymptoms;

  const HomeopathyChiefComplaint({
    this.complaint = '',
    this.location = '',
    this.sensationDescription = '',
    this.onset = '',
    this.duration = '',
    this.frequency = '',
    this.progression = '',
    this.triggeringCauses = '',
    this.associatedSymptoms = '',
  });

  bool get isCompleted =>
      complaint.trim().isNotEmpty || sensationDescription.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'complaint': complaint,
        'location': location,
        'sensationDescription': sensationDescription,
        'onset': onset,
        'duration': duration,
        'frequency': frequency,
        'progression': progression,
        'triggeringCauses': triggeringCauses,
        'associatedSymptoms': associatedSymptoms,
      };

  factory HomeopathyChiefComplaint.fromMap(Map<String, dynamic> map) =>
      HomeopathyChiefComplaint(
        complaint: map['complaint'] as String? ?? '',
        location: map['location'] as String? ?? '',
        sensationDescription: map['sensationDescription'] as String? ?? '',
        onset: map['onset'] as String? ?? '',
        duration: map['duration'] as String? ?? '',
        frequency: map['frequency'] as String? ?? '',
        progression: map['progression'] as String? ?? '',
        triggeringCauses: map['triggeringCauses'] as String? ?? '',
        associatedSymptoms: map['associatedSymptoms'] as String? ?? '',
      );

  HomeopathyChiefComplaint copyWith({
    String? complaint,
    String? location,
    String? sensationDescription,
    String? onset,
    String? duration,
    String? frequency,
    String? progression,
    String? triggeringCauses,
    String? associatedSymptoms,
  }) =>
      HomeopathyChiefComplaint(
        complaint: complaint ?? this.complaint,
        location: location ?? this.location,
        sensationDescription:
            sensationDescription ?? this.sensationDescription,
        onset: onset ?? this.onset,
        duration: duration ?? this.duration,
        frequency: frequency ?? this.frequency,
        progression: progression ?? this.progression,
        triggeringCauses: triggeringCauses ?? this.triggeringCauses,
        associatedSymptoms: associatedSymptoms ?? this.associatedSymptoms,
      );
}

/// C. Modalities (Aggravation & Amelioration)
class HomeopathyModalities {
  final String aggravatingFactors;
  final String amelioratingFactors;
  final String timePatterns;
  final String positionModalities;
  final String motionModalities;
  final String restModalities;
  final String temperatureWeather;
  final String foodDrinkModalities;
  final String otherTriggers;

  const HomeopathyModalities({
    this.aggravatingFactors = '',
    this.amelioratingFactors = '',
    this.timePatterns = '',
    this.positionModalities = '',
    this.motionModalities = '',
    this.restModalities = '',
    this.temperatureWeather = '',
    this.foodDrinkModalities = '',
    this.otherTriggers = '',
  });

  bool get isCompleted =>
      aggravatingFactors.trim().isNotEmpty ||
      amelioratingFactors.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'aggravatingFactors': aggravatingFactors,
        'amelioratingFactors': amelioratingFactors,
        'timePatterns': timePatterns,
        'positionModalities': positionModalities,
        'motionModalities': motionModalities,
        'restModalities': restModalities,
        'temperatureWeather': temperatureWeather,
        'foodDrinkModalities': foodDrinkModalities,
        'otherTriggers': otherTriggers,
      };

  factory HomeopathyModalities.fromMap(Map<String, dynamic> map) =>
      HomeopathyModalities(
        aggravatingFactors: map['aggravatingFactors'] as String? ?? '',
        amelioratingFactors: map['amelioratingFactors'] as String? ?? '',
        timePatterns: map['timePatterns'] as String? ?? '',
        positionModalities: map['positionModalities'] as String? ?? '',
        motionModalities: map['motionModalities'] as String? ?? '',
        restModalities: map['restModalities'] as String? ?? '',
        temperatureWeather: map['temperatureWeather'] as String? ?? '',
        foodDrinkModalities: map['foodDrinkModalities'] as String? ?? '',
        otherTriggers: map['otherTriggers'] as String? ?? '',
      );

  HomeopathyModalities copyWith({
    String? aggravatingFactors,
    String? amelioratingFactors,
    String? timePatterns,
    String? positionModalities,
    String? motionModalities,
    String? restModalities,
    String? temperatureWeather,
    String? foodDrinkModalities,
    String? otherTriggers,
  }) =>
      HomeopathyModalities(
        aggravatingFactors: aggravatingFactors ?? this.aggravatingFactors,
        amelioratingFactors: amelioratingFactors ?? this.amelioratingFactors,
        timePatterns: timePatterns ?? this.timePatterns,
        positionModalities: positionModalities ?? this.positionModalities,
        motionModalities: motionModalities ?? this.motionModalities,
        restModalities: restModalities ?? this.restModalities,
        temperatureWeather: temperatureWeather ?? this.temperatureWeather,
        foodDrinkModalities: foodDrinkModalities ?? this.foodDrinkModalities,
        otherTriggers: otherTriggers ?? this.otherTriggers,
      );
}

/// D. General Symptoms (Physical Generals & Thermals)
class HomeopathyGeneralSymptoms {
  final String appetite;
  final List<String> cravingsDesires;
  final List<String> aversionsDislikes;
  final String thirst;
  final String thirstStyle;
  final String stools;
  final String urine;
  final String sleepPattern;
  final String skinState;
  final String energyWeakness;
  final HomeopathyThermalState thermalState;
  final String perspiration;
  final String perspirationLocation;
  final String perspirationOdour;
  final String hungerTime;
  final String hungerReaction;
  final String eatingSpeed;
  final String thirstTime;
  final String tasteChanges;
  final Map<String, String> foodPreferences;

  const HomeopathyGeneralSymptoms({
    this.appetite = '',
    this.cravingsDesires = const [],
    this.aversionsDislikes = const [],
    this.thirst = '',
    this.thirstStyle = '',
    this.stools = '',
    this.urine = '',
    this.sleepPattern = '',
    this.skinState = '',
    this.energyWeakness = '',
    this.thermalState = HomeopathyThermalState.unspecified,
    this.perspiration = '',
    this.perspirationLocation = '',
    this.perspirationOdour = '',
    this.hungerTime = '',
    this.hungerReaction = '',
    this.eatingSpeed = '',
    this.thirstTime = '',
    this.tasteChanges = '',
    this.foodPreferences = const {},
  });

  bool get isCompleted =>
      thermalState != HomeopathyThermalState.unspecified ||
      cravingsDesires.isNotEmpty ||
      thirst.trim().isNotEmpty ||
      thirstStyle.trim().isNotEmpty ||
      hungerTime.trim().isNotEmpty ||
      thirstTime.trim().isNotEmpty ||
      tasteChanges.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'appetite': appetite,
        'cravingsDesires': cravingsDesires,
        'aversionsDislikes': aversionsDislikes,
        'thirst': thirst,
        'thirstStyle': thirstStyle,
        'stools': stools,
        'urine': urine,
        'sleepPattern': sleepPattern,
        'skinState': skinState,
        'energyWeakness': energyWeakness,
        'thermalState': thermalState.name,
        'perspiration': perspiration,
        'perspirationLocation': perspirationLocation,
        'perspirationOdour': perspirationOdour,
        'hungerTime': hungerTime,
        'hungerReaction': hungerReaction,
        'eatingSpeed': eatingSpeed,
        'thirstTime': thirstTime,
        'tasteChanges': tasteChanges,
        'foodPreferences': foodPreferences,
      };

  factory HomeopathyGeneralSymptoms.fromMap(Map<String, dynamic> map) =>
      HomeopathyGeneralSymptoms(
        appetite: map['appetite'] as String? ?? '',
        cravingsDesires: (map['cravingsDesires'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        aversionsDislikes: (map['aversionsDislikes'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        thirst: map['thirst'] as String? ?? '',
        thirstStyle: map['thirstStyle'] as String? ?? '',
        stools: map['stools'] as String? ?? '',
        urine: map['urine'] as String? ?? '',
        sleepPattern: map['sleepPattern'] as String? ?? '',
        skinState: map['skinState'] as String? ?? '',
        energyWeakness: map['energyWeakness'] as String? ?? '',
        thermalState:
            HomeopathyThermalState.fromString(map['thermalState'] as String?),
        perspiration: map['perspiration'] as String? ?? '',
        perspirationLocation: map['perspirationLocation'] as String? ?? '',
        perspirationOdour: map['perspirationOdour'] as String? ?? '',
        hungerTime: map['hungerTime'] as String? ?? '',
        hungerReaction: map['hungerReaction'] as String? ?? '',
        eatingSpeed: map['eatingSpeed'] as String? ?? '',
        thirstTime: map['thirstTime'] as String? ?? '',
        tasteChanges: map['tasteChanges'] as String? ?? '',
        foodPreferences: (map['foodPreferences'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v.toString())) ??
            const {},
      );

  HomeopathyGeneralSymptoms copyWith({
    String? appetite,
    List<String>? cravingsDesires,
    List<String>? aversionsDislikes,
    String? thirst,
    String? thirstStyle,
    String? stools,
    String? urine,
    String? sleepPattern,
    String? skinState,
    String? energyWeakness,
    HomeopathyThermalState? thermalState,
    String? perspiration,
    String? perspirationLocation,
    String? perspirationOdour,
    String? hungerTime,
    String? hungerReaction,
    String? eatingSpeed,
    String? thirstTime,
    String? tasteChanges,
    Map<String, String>? foodPreferences,
  }) =>
      HomeopathyGeneralSymptoms(
        appetite: appetite ?? this.appetite,
        cravingsDesires: cravingsDesires ?? this.cravingsDesires,
        aversionsDislikes: aversionsDislikes ?? this.aversionsDislikes,
        thirst: thirst ?? this.thirst,
        thirstStyle: thirstStyle ?? this.thirstStyle,
        stools: stools ?? this.stools,
        urine: urine ?? this.urine,
        sleepPattern: sleepPattern ?? this.sleepPattern,
        skinState: skinState ?? this.skinState,
        energyWeakness: energyWeakness ?? this.energyWeakness,
        thermalState: thermalState ?? this.thermalState,
        perspiration: perspiration ?? this.perspiration,
        perspirationLocation: perspirationLocation ?? this.perspirationLocation,
        perspirationOdour: perspirationOdour ?? this.perspirationOdour,
        hungerTime: hungerTime ?? this.hungerTime,
        hungerReaction: hungerReaction ?? this.hungerReaction,
        eatingSpeed: eatingSpeed ?? this.eatingSpeed,
        thirstTime: thirstTime ?? this.thirstTime,
        tasteChanges: tasteChanges ?? this.tasteChanges,
        foodPreferences: foodPreferences ?? this.foodPreferences,
      );
}

/// E. Physical & Systemic Symptoms (Head, Respiratory, Digestive, Fever Stages, Pain)
class HomeopathyPhysicalSymptoms {
  final String rheumatologyJoints;
  final String cnsNervous;
  final String faceEnt;
  final String respiratory;
  final String thermoregulationFever;
  final String feverChillStage;
  final String feverHeatStage;
  final String feverSweatStage;
  final String feverPeriodicity;
  final String coughType;
  final String sputumDetails;
  final String coughTasteInMouth;
  final String digestiveStoolDetails;
  final String headVertigoSymptoms;
  final String painCharacteristics;
  final String painLocation;
  final int painIntensity; // 1 to 10 scale
  final String painModalities;

  const HomeopathyPhysicalSymptoms({
    this.rheumatologyJoints = '',
    this.cnsNervous = '',
    this.faceEnt = '',
    this.respiratory = '',
    this.thermoregulationFever = '',
    this.feverChillStage = '',
    this.feverHeatStage = '',
    this.feverSweatStage = '',
    this.feverPeriodicity = '',
    this.coughType = '',
    this.sputumDetails = '',
    this.coughTasteInMouth = '',
    this.digestiveStoolDetails = '',
    this.headVertigoSymptoms = '',
    this.painCharacteristics = '',
    this.painLocation = '',
    this.painIntensity = 0,
    this.painModalities = '',
  });

  bool get isCompleted =>
      rheumatologyJoints.trim().isNotEmpty ||
      respiratory.trim().isNotEmpty ||
      feverChillStage.trim().isNotEmpty ||
      digestiveStoolDetails.trim().isNotEmpty ||
      painCharacteristics.trim().isNotEmpty ||
      faceEnt.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'rheumatologyJoints': rheumatologyJoints,
        'cnsNervous': cnsNervous,
        'faceEnt': faceEnt,
        'respiratory': respiratory,
        'thermoregulationFever': thermoregulationFever,
        'feverChillStage': feverChillStage,
        'feverHeatStage': feverHeatStage,
        'feverSweatStage': feverSweatStage,
        'feverPeriodicity': feverPeriodicity,
        'coughType': coughType,
        'sputumDetails': sputumDetails,
        'coughTasteInMouth': coughTasteInMouth,
        'digestiveStoolDetails': digestiveStoolDetails,
        'headVertigoSymptoms': headVertigoSymptoms,
        'painCharacteristics': painCharacteristics,
        'painLocation': painLocation,
        'painIntensity': painIntensity,
        'painModalities': painModalities,
      };

  factory HomeopathyPhysicalSymptoms.fromMap(Map<String, dynamic> map) =>
      HomeopathyPhysicalSymptoms(
        rheumatologyJoints: map['rheumatologyJoints'] as String? ?? '',
        cnsNervous: map['cnsNervous'] as String? ?? '',
        faceEnt: map['faceEnt'] as String? ?? '',
        respiratory: map['respiratory'] as String? ?? '',
        thermoregulationFever: map['thermoregulationFever'] as String? ?? '',
        feverChillStage: map['feverChillStage'] as String? ?? '',
        feverHeatStage: map['feverHeatStage'] as String? ?? '',
        feverSweatStage: map['feverSweatStage'] as String? ?? '',
        feverPeriodicity: map['feverPeriodicity'] as String? ?? '',
        coughType: map['coughType'] as String? ?? '',
        sputumDetails: map['sputumDetails'] as String? ?? '',
        coughTasteInMouth: map['coughTasteInMouth'] as String? ?? '',
        digestiveStoolDetails: map['digestiveStoolDetails'] as String? ?? '',
        headVertigoSymptoms: map['headVertigoSymptoms'] as String? ?? '',
        painCharacteristics: map['painCharacteristics'] as String? ?? '',
        painLocation: map['painLocation'] as String? ?? '',
        painIntensity: (map['painIntensity'] as num?)?.toInt() ?? 0,
        painModalities: map['painModalities'] as String? ?? '',
      );

  HomeopathyPhysicalSymptoms copyWith({
    String? rheumatologyJoints,
    String? cnsNervous,
    String? faceEnt,
    String? respiratory,
    String? thermoregulationFever,
    String? feverChillStage,
    String? feverHeatStage,
    String? feverSweatStage,
    String? feverPeriodicity,
    String? coughType,
    String? sputumDetails,
    String? coughTasteInMouth,
    String? digestiveStoolDetails,
    String? headVertigoSymptoms,
    String? painCharacteristics,
    String? painLocation,
    int? painIntensity,
    String? painModalities,
  }) =>
      HomeopathyPhysicalSymptoms(
        rheumatologyJoints: rheumatologyJoints ?? this.rheumatologyJoints,
        cnsNervous: cnsNervous ?? this.cnsNervous,
        faceEnt: faceEnt ?? this.faceEnt,
        respiratory: respiratory ?? this.respiratory,
        thermoregulationFever:
            thermoregulationFever ?? this.thermoregulationFever,
        feverChillStage: feverChillStage ?? this.feverChillStage,
        feverHeatStage: feverHeatStage ?? this.feverHeatStage,
        feverSweatStage: feverSweatStage ?? this.feverSweatStage,
        feverPeriodicity: feverPeriodicity ?? this.feverPeriodicity,
        coughType: coughType ?? this.coughType,
        sputumDetails: sputumDetails ?? this.sputumDetails,
        coughTasteInMouth: coughTasteInMouth ?? this.coughTasteInMouth,
        digestiveStoolDetails:
            digestiveStoolDetails ?? this.digestiveStoolDetails,
        headVertigoSymptoms: headVertigoSymptoms ?? this.headVertigoSymptoms,
        painCharacteristics: painCharacteristics ?? this.painCharacteristics,
        painLocation: painLocation ?? this.painLocation,
        painIntensity: painIntensity ?? this.painIntensity,
        painModalities: painModalities ?? this.painModalities,
      );
}

/// F. Female / Reproductive History
class HomeopathyFemaleHistory {
  final String mensesCycle;
  final String mensesDuration;
  final String flowCharacter;
  final String menopauseDetails;
  final String menstrualSuppressionEffects;
  final String leucorrhoeaDetails;
  final String obstetricHistory;

  const HomeopathyFemaleHistory({
    this.mensesCycle = '',
    this.mensesDuration = '',
    this.flowCharacter = '',
    this.menopauseDetails = '',
    this.menstrualSuppressionEffects = '',
    this.leucorrhoeaDetails = '',
    this.obstetricHistory = '',
  });

  bool get isCompleted =>
      mensesCycle.trim().isNotEmpty || flowCharacter.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'mensesCycle': mensesCycle,
        'mensesDuration': mensesDuration,
        'flowCharacter': flowCharacter,
        'menopauseDetails': menopauseDetails,
        'menstrualSuppressionEffects': menstrualSuppressionEffects,
        'leucorrhoeaDetails': leucorrhoeaDetails,
        'obstetricHistory': obstetricHistory,
      };

  factory HomeopathyFemaleHistory.fromMap(Map<String, dynamic> map) =>
      HomeopathyFemaleHistory(
        mensesCycle: map['mensesCycle'] as String? ?? '',
        mensesDuration: map['mensesDuration'] as String? ?? '',
        flowCharacter: map['flowCharacter'] as String? ?? '',
        menopauseDetails: map['menopauseDetails'] as String? ?? '',
        menstrualSuppressionEffects:
            map['menstrualSuppressionEffects'] as String? ?? '',
        leucorrhoeaDetails: map['leucorrhoeaDetails'] as String? ?? '',
        obstetricHistory: map['obstetricHistory'] as String? ?? '',
      );

  HomeopathyFemaleHistory copyWith({
    String? mensesCycle,
    String? mensesDuration,
    String? flowCharacter,
    String? menopauseDetails,
    String? menstrualSuppressionEffects,
    String? leucorrhoeaDetails,
    String? obstetricHistory,
  }) =>
      HomeopathyFemaleHistory(
        mensesCycle: mensesCycle ?? this.mensesCycle,
        mensesDuration: mensesDuration ?? this.mensesDuration,
        flowCharacter: flowCharacter ?? this.flowCharacter,
        menopauseDetails: menopauseDetails ?? this.menopauseDetails,
        menstrualSuppressionEffects:
            menstrualSuppressionEffects ?? this.menstrualSuppressionEffects,
        leucorrhoeaDetails: leucorrhoeaDetails ?? this.leucorrhoeaDetails,
        obstetricHistory: obstetricHistory ?? this.obstetricHistory,
      );
}

/// G. Mental & Emotional State (Personality, Fears, Stress, Relationships & Demeanor)
class HomeopathyMentalEmotional {
  final String disposition;
  final List<String> fears;
  final String anxietyTriggers;
  final String companyVsSolitude;
  final String reactionToConsolation;
  final String emotionalAetiology;
  final String timeOfDayMood;
  final String behavioralChanges;
  final String familyDynamics;
  final String spouseRelationship;
  final String childrenRelationship;
  final String inlawsRelationship;
  final String colleaguesWorkStress;
  final String majorTensions;
  final String reactionToDisease;
  final String dullnessVsRestlessness;
  final String facialExpression;
  final String mentalShiftSinceIllness;

  // --- PDF General Case Sheet Q1–Q18 personality questions ---
  final String upsetWorryTriggers; // Q1
  final String fearDetails; // Q3 — detailed text beyond fears list
  final String introvertExtrovert; // Q4
  final String stressHistory; // Q5
  final String stressCopingMethods; // Q7
  final String sensitivityDetails; // Q8
  final String fixedHabits; // Q9
  final String angerBodySymptoms; // Q10
  final String disorderSensitivity; // Q12
  final String greatestGrief; // Q13
  final String greatestJoys; // Q14
  final String deeplyLikedActivities; // Q15
  final String deeplyDislikedMatters; // Q16
  final String disagreeableMindAspects; // Q17
  final String lifeSituationPicture; // Q18

  const HomeopathyMentalEmotional({
    this.disposition = '',
    this.fears = const [],
    this.anxietyTriggers = '',
    this.companyVsSolitude = '',
    this.reactionToConsolation = '',
    this.emotionalAetiology = '',
    this.timeOfDayMood = '',
    this.behavioralChanges = '',
    this.familyDynamics = '',
    this.spouseRelationship = '',
    this.childrenRelationship = '',
    this.inlawsRelationship = '',
    this.colleaguesWorkStress = '',
    this.majorTensions = '',
    this.reactionToDisease = '',
    this.dullnessVsRestlessness = '',
    this.facialExpression = '',
    this.mentalShiftSinceIllness = '',
    this.upsetWorryTriggers = '',
    this.fearDetails = '',
    this.introvertExtrovert = '',
    this.stressHistory = '',
    this.stressCopingMethods = '',
    this.sensitivityDetails = '',
    this.fixedHabits = '',
    this.angerBodySymptoms = '',
    this.disorderSensitivity = '',
    this.greatestGrief = '',
    this.greatestJoys = '',
    this.deeplyLikedActivities = '',
    this.deeplyDislikedMatters = '',
    this.disagreeableMindAspects = '',
    this.lifeSituationPicture = '',
  });

  bool get isCompleted =>
      disposition.trim().isNotEmpty ||
      fears.isNotEmpty ||
      familyDynamics.trim().isNotEmpty ||
      reactionToDisease.trim().isNotEmpty ||
      reactionToConsolation.trim().isNotEmpty ||
      upsetWorryTriggers.trim().isNotEmpty ||
      fearDetails.trim().isNotEmpty ||
      greatestGrief.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'disposition': disposition,
        'fears': fears,
        'anxietyTriggers': anxietyTriggers,
        'companyVsSolitude': companyVsSolitude,
        'reactionToConsolation': reactionToConsolation,
        'emotionalAetiology': emotionalAetiology,
        'timeOfDayMood': timeOfDayMood,
        'behavioralChanges': behavioralChanges,
        'familyDynamics': familyDynamics,
        'spouseRelationship': spouseRelationship,
        'childrenRelationship': childrenRelationship,
        'inlawsRelationship': inlawsRelationship,
        'colleaguesWorkStress': colleaguesWorkStress,
        'majorTensions': majorTensions,
        'reactionToDisease': reactionToDisease,
        'dullnessVsRestlessness': dullnessVsRestlessness,
        'facialExpression': facialExpression,
        'mentalShiftSinceIllness': mentalShiftSinceIllness,
        'upsetWorryTriggers': upsetWorryTriggers,
        'fearDetails': fearDetails,
        'introvertExtrovert': introvertExtrovert,
        'stressHistory': stressHistory,
        'stressCopingMethods': stressCopingMethods,
        'sensitivityDetails': sensitivityDetails,
        'fixedHabits': fixedHabits,
        'angerBodySymptoms': angerBodySymptoms,
        'disorderSensitivity': disorderSensitivity,
        'greatestGrief': greatestGrief,
        'greatestJoys': greatestJoys,
        'deeplyLikedActivities': deeplyLikedActivities,
        'deeplyDislikedMatters': deeplyDislikedMatters,
        'disagreeableMindAspects': disagreeableMindAspects,
        'lifeSituationPicture': lifeSituationPicture,
      };

  factory HomeopathyMentalEmotional.fromMap(Map<String, dynamic> map) =>
      HomeopathyMentalEmotional(
        disposition: map['disposition'] as String? ?? '',
        fears: (map['fears'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        anxietyTriggers: map['anxietyTriggers'] as String? ?? '',
        companyVsSolitude: map['companyVsSolitude'] as String? ?? '',
        reactionToConsolation: map['reactionToConsolation'] as String? ?? '',
        emotionalAetiology: map['emotionalAetiology'] as String? ?? '',
        timeOfDayMood: map['timeOfDayMood'] as String? ?? '',
        behavioralChanges: map['behavioralChanges'] as String? ?? '',
        familyDynamics: map['familyDynamics'] as String? ?? '',
        spouseRelationship: map['spouseRelationship'] as String? ?? '',
        childrenRelationship: map['childrenRelationship'] as String? ?? '',
        inlawsRelationship: map['inlawsRelationship'] as String? ?? '',
        colleaguesWorkStress: map['colleaguesWorkStress'] as String? ?? '',
        majorTensions: map['majorTensions'] as String? ?? '',
        reactionToDisease: map['reactionToDisease'] as String? ?? '',
        dullnessVsRestlessness: map['dullnessVsRestlessness'] as String? ?? '',
        facialExpression: map['facialExpression'] as String? ?? '',
        mentalShiftSinceIllness:
            map['mentalShiftSinceIllness'] as String? ?? '',
        upsetWorryTriggers: map['upsetWorryTriggers'] as String? ?? '',
        fearDetails: map['fearDetails'] as String? ?? '',
        introvertExtrovert: map['introvertExtrovert'] as String? ?? '',
        stressHistory: map['stressHistory'] as String? ?? '',
        stressCopingMethods: map['stressCopingMethods'] as String? ?? '',
        sensitivityDetails: map['sensitivityDetails'] as String? ?? '',
        fixedHabits: map['fixedHabits'] as String? ?? '',
        angerBodySymptoms: map['angerBodySymptoms'] as String? ?? '',
        disorderSensitivity: map['disorderSensitivity'] as String? ?? '',
        greatestGrief: map['greatestGrief'] as String? ?? '',
        greatestJoys: map['greatestJoys'] as String? ?? '',
        deeplyLikedActivities: map['deeplyLikedActivities'] as String? ?? '',
        deeplyDislikedMatters: map['deeplyDislikedMatters'] as String? ?? '',
        disagreeableMindAspects: map['disagreeableMindAspects'] as String? ?? '',
        lifeSituationPicture: map['lifeSituationPicture'] as String? ?? '',
      );

  HomeopathyMentalEmotional copyWith({
    String? disposition,
    List<String>? fears,
    String? anxietyTriggers,
    String? companyVsSolitude,
    String? reactionToConsolation,
    String? emotionalAetiology,
    String? timeOfDayMood,
    String? behavioralChanges,
    String? familyDynamics,
    String? spouseRelationship,
    String? childrenRelationship,
    String? inlawsRelationship,
    String? colleaguesWorkStress,
    String? majorTensions,
    String? reactionToDisease,
    String? dullnessVsRestlessness,
    String? facialExpression,
    String? mentalShiftSinceIllness,
    String? upsetWorryTriggers,
    String? fearDetails,
    String? introvertExtrovert,
    String? stressHistory,
    String? stressCopingMethods,
    String? sensitivityDetails,
    String? fixedHabits,
    String? angerBodySymptoms,
    String? disorderSensitivity,
    String? greatestGrief,
    String? greatestJoys,
    String? deeplyLikedActivities,
    String? deeplyDislikedMatters,
    String? disagreeableMindAspects,
    String? lifeSituationPicture,
  }) =>
      HomeopathyMentalEmotional(
        disposition: disposition ?? this.disposition,
        fears: fears ?? this.fears,
        anxietyTriggers: anxietyTriggers ?? this.anxietyTriggers,
        companyVsSolitude: companyVsSolitude ?? this.companyVsSolitude,
        reactionToConsolation:
            reactionToConsolation ?? this.reactionToConsolation,
        emotionalAetiology: emotionalAetiology ?? this.emotionalAetiology,
        timeOfDayMood: timeOfDayMood ?? this.timeOfDayMood,
        behavioralChanges: behavioralChanges ?? this.behavioralChanges,
        familyDynamics: familyDynamics ?? this.familyDynamics,
        spouseRelationship: spouseRelationship ?? this.spouseRelationship,
        childrenRelationship:
            childrenRelationship ?? this.childrenRelationship,
        inlawsRelationship: inlawsRelationship ?? this.inlawsRelationship,
        colleaguesWorkStress:
            colleaguesWorkStress ?? this.colleaguesWorkStress,
        majorTensions: majorTensions ?? this.majorTensions,
        reactionToDisease: reactionToDisease ?? this.reactionToDisease,
        dullnessVsRestlessness:
            dullnessVsRestlessness ?? this.dullnessVsRestlessness,
        facialExpression: facialExpression ?? this.facialExpression,
        mentalShiftSinceIllness:
            mentalShiftSinceIllness ?? this.mentalShiftSinceIllness,
        upsetWorryTriggers: upsetWorryTriggers ?? this.upsetWorryTriggers,
        fearDetails: fearDetails ?? this.fearDetails,
        introvertExtrovert: introvertExtrovert ?? this.introvertExtrovert,
        stressHistory: stressHistory ?? this.stressHistory,
        stressCopingMethods: stressCopingMethods ?? this.stressCopingMethods,
        sensitivityDetails: sensitivityDetails ?? this.sensitivityDetails,
        fixedHabits: fixedHabits ?? this.fixedHabits,
        angerBodySymptoms: angerBodySymptoms ?? this.angerBodySymptoms,
        disorderSensitivity: disorderSensitivity ?? this.disorderSensitivity,
        greatestGrief: greatestGrief ?? this.greatestGrief,
        greatestJoys: greatestJoys ?? this.greatestJoys,
        deeplyLikedActivities: deeplyLikedActivities ?? this.deeplyLikedActivities,
        deeplyDislikedMatters: deeplyDislikedMatters ?? this.deeplyDislikedMatters,
        disagreeableMindAspects: disagreeableMindAspects ?? this.disagreeableMindAspects,
        lifeSituationPicture: lifeSituationPicture ?? this.lifeSituationPicture,
      );
}

/// H. Dreams & Sleep
class HomeopathyDreamsSleep {
  final String sleepQuality;
  final String sleepDisturbances;
  final List<String> recurringDreams;
  final String dreamCharacteristics;
  final String sleepPosture; // Q19 — back, side, abdomen, etc.
  final String sleepPositionRestrictions; // Q20 — can’t sleep in which position?
  final String sleepBehaviors; // Q21 — snore/grind teeth/drool/walk/talk/moan/etc.
  final String childhoodDreams; // Q24

  const HomeopathyDreamsSleep({
    this.sleepQuality = '',
    this.sleepDisturbances = '',
    this.recurringDreams = const [],
    this.dreamCharacteristics = '',
    this.sleepPosture = '',
    this.sleepPositionRestrictions = '',
    this.sleepBehaviors = '',
    this.childhoodDreams = '',
  });

  bool get isCompleted =>
      sleepQuality.trim().isNotEmpty ||
      recurringDreams.isNotEmpty ||
      sleepPosture.trim().isNotEmpty ||
      sleepBehaviors.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'sleepQuality': sleepQuality,
        'sleepDisturbances': sleepDisturbances,
        'recurringDreams': recurringDreams,
        'dreamCharacteristics': dreamCharacteristics,
        'sleepPosture': sleepPosture,
        'sleepPositionRestrictions': sleepPositionRestrictions,
        'sleepBehaviors': sleepBehaviors,
        'childhoodDreams': childhoodDreams,
      };

  factory HomeopathyDreamsSleep.fromMap(Map<String, dynamic> map) =>
      HomeopathyDreamsSleep(
        sleepQuality: map['sleepQuality'] as String? ?? '',
        sleepDisturbances: map['sleepDisturbances'] as String? ?? '',
        recurringDreams: (map['recurringDreams'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        dreamCharacteristics: map['dreamCharacteristics'] as String? ?? '',
        sleepPosture: map['sleepPosture'] as String? ?? '',
        sleepPositionRestrictions: map['sleepPositionRestrictions'] as String? ?? '',
        sleepBehaviors: map['sleepBehaviors'] as String? ?? '',
        childhoodDreams: map['childhoodDreams'] as String? ?? '',
      );

  HomeopathyDreamsSleep copyWith({
    String? sleepQuality,
    String? sleepDisturbances,
    List<String>? recurringDreams,
    String? dreamCharacteristics,
    String? sleepPosture,
    String? sleepPositionRestrictions,
    String? sleepBehaviors,
    String? childhoodDreams,
  }) =>
      HomeopathyDreamsSleep(
        sleepQuality: sleepQuality ?? this.sleepQuality,
        sleepDisturbances: sleepDisturbances ?? this.sleepDisturbances,
        recurringDreams: recurringDreams ?? this.recurringDreams,
        dreamCharacteristics:
            dreamCharacteristics ?? this.dreamCharacteristics,
        sleepPosture: sleepPosture ?? this.sleepPosture,
        sleepPositionRestrictions:
            sleepPositionRestrictions ?? this.sleepPositionRestrictions,
        sleepBehaviors: sleepBehaviors ?? this.sleepBehaviors,
        childhoodDreams: childhoodDreams ?? this.childhoodDreams,
      );
}

/// I. Sexual History (Sensitive & Collapsible)
class HomeopathySexualHistory {
  final String desireLevel;
  final String complaintsConcerns;
  final String notes;

  const HomeopathySexualHistory({
    this.desireLevel = '',
    this.complaintsConcerns = '',
    this.notes = '',
  });

  bool get isCompleted =>
      desireLevel.trim().isNotEmpty || complaintsConcerns.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'desireLevel': desireLevel,
        'complaintsConcerns': complaintsConcerns,
        'notes': notes,
      };

  factory HomeopathySexualHistory.fromMap(Map<String, dynamic> map) =>
      HomeopathySexualHistory(
        desireLevel: map['desireLevel'] as String? ?? '',
        complaintsConcerns: map['complaintsConcerns'] as String? ?? '',
        notes: map['notes'] as String? ?? '',
      );

  HomeopathySexualHistory copyWith({
    String? desireLevel,
    String? complaintsConcerns,
    String? notes,
  }) =>
      HomeopathySexualHistory(
        desireLevel: desireLevel ?? this.desireLevel,
        complaintsConcerns: complaintsConcerns ?? this.complaintsConcerns,
        notes: notes ?? this.notes,
      );
}

/// J. Medical / Health History
class HomeopathyMedicalHistory {
  final String pastIllnesses;
  final String surgicalHistory;
  final String pastMedications;
  final String allergies;
  final String vaccinationReactions;
  final String familyHistory;

  const HomeopathyMedicalHistory({
    this.pastIllnesses = '',
    this.surgicalHistory = '',
    this.pastMedications = '',
    this.allergies = '',
    this.vaccinationReactions = '',
    this.familyHistory = '',
  });

  bool get isCompleted =>
      pastIllnesses.trim().isNotEmpty ||
      allergies.trim().isNotEmpty ||
      familyHistory.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'pastIllnesses': pastIllnesses,
        'surgicalHistory': surgicalHistory,
        'pastMedications': pastMedications,
        'allergies': allergies,
        'vaccinationReactions': vaccinationReactions,
        'familyHistory': familyHistory,
      };

  factory HomeopathyMedicalHistory.fromMap(Map<String, dynamic> map) =>
      HomeopathyMedicalHistory(
        pastIllnesses: map['pastIllnesses'] as String? ?? '',
        surgicalHistory: map['surgicalHistory'] as String? ?? '',
        pastMedications: map['pastMedications'] as String? ?? '',
        allergies: map['allergies'] as String? ?? '',
        vaccinationReactions: map['vaccinationReactions'] as String? ?? '',
        familyHistory: map['familyHistory'] as String? ?? '',
      );

  HomeopathyMedicalHistory copyWith({
    String? pastIllnesses,
    String? surgicalHistory,
    String? pastMedications,
    String? allergies,
    String? vaccinationReactions,
    String? familyHistory,
  }) =>
      HomeopathyMedicalHistory(
        pastIllnesses: pastIllnesses ?? this.pastIllnesses,
        surgicalHistory: surgicalHistory ?? this.surgicalHistory,
        pastMedications: pastMedications ?? this.pastMedications,
        allergies: allergies ?? this.allergies,
        vaccinationReactions:
            vaccinationReactions ?? this.vaccinationReactions,
        familyHistory: familyHistory ?? this.familyHistory,
      );
}

/// K. Physical Examination
class HomeopathyPhysicalExam {
  final String constitutionBuild;
  final String tongueExamination;
  final String nailsPulseBP;
  final String sensitiveAreas;
  final String clinicalObservations;

  const HomeopathyPhysicalExam({
    this.constitutionBuild = '',
    this.tongueExamination = '',
    this.nailsPulseBP = '',
    this.sensitiveAreas = '',
    this.clinicalObservations = '',
  });

  bool get isCompleted =>
      tongueExamination.trim().isNotEmpty ||
      clinicalObservations.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'constitutionBuild': constitutionBuild,
        'tongueExamination': tongueExamination,
        'nailsPulseBP': nailsPulseBP,
        'sensitiveAreas': sensitiveAreas,
        'clinicalObservations': clinicalObservations,
      };

  factory HomeopathyPhysicalExam.fromMap(Map<String, dynamic> map) =>
      HomeopathyPhysicalExam(
        constitutionBuild: map['constitutionBuild'] as String? ?? '',
        tongueExamination: map['tongueExamination'] as String? ?? '',
        nailsPulseBP: map['nailsPulseBP'] as String? ?? '',
        sensitiveAreas: map['sensitiveAreas'] as String? ?? '',
        clinicalObservations: map['clinicalObservations'] as String? ?? '',
      );

  HomeopathyPhysicalExam copyWith({
    String? constitutionBuild,
    String? tongueExamination,
    String? nailsPulseBP,
    String? sensitiveAreas,
    String? clinicalObservations,
  }) =>
      HomeopathyPhysicalExam(
        constitutionBuild: constitutionBuild ?? this.constitutionBuild,
        tongueExamination: tongueExamination ?? this.tongueExamination,
        nailsPulseBP: nailsPulseBP ?? this.nailsPulseBP,
        sensitiveAreas: sensitiveAreas ?? this.sensitiveAreas,
        clinicalObservations:
            clinicalObservations ?? this.clinicalObservations,
      );
}

/// L. Investigations
class HomeopathyInvestigations {
  final String labReports;
  final String imagingDiagnosticNotes;

  const HomeopathyInvestigations({
    this.labReports = '',
    this.imagingDiagnosticNotes = '',
  });

  bool get isCompleted =>
      labReports.trim().isNotEmpty || imagingDiagnosticNotes.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'labReports': labReports,
        'imagingDiagnosticNotes': imagingDiagnosticNotes,
      };

  factory HomeopathyInvestigations.fromMap(Map<String, dynamic> map) =>
      HomeopathyInvestigations(
        labReports: map['labReports'] as String? ?? '',
        imagingDiagnosticNotes:
            map['imagingDiagnosticNotes'] as String? ?? '',
      );

  HomeopathyInvestigations copyWith({
    String? labReports,
    String? imagingDiagnosticNotes,
  }) =>
      HomeopathyInvestigations(
        labReports: labReports ?? this.labReports,
        imagingDiagnosticNotes:
            imagingDiagnosticNotes ?? this.imagingDiagnosticNotes,
      );
}

/// M. Peculiar Symptoms (SRP / Keynote Indicators)
class HomeopathyPeculiarSymptoms {
  final String peculiarSRP;
  final String keynoteObservations;

  const HomeopathyPeculiarSymptoms({
    this.peculiarSRP = '',
    this.keynoteObservations = '',
  });

  bool get isCompleted => peculiarSRP.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'peculiarSRP': peculiarSRP,
        'keynoteObservations': keynoteObservations,
      };

  factory HomeopathyPeculiarSymptoms.fromMap(Map<String, dynamic> map) =>
      HomeopathyPeculiarSymptoms(
        peculiarSRP: map['peculiarSRP'] as String? ?? '',
        keynoteObservations: map['keynoteObservations'] as String? ?? '',
      );

  HomeopathyPeculiarSymptoms copyWith({
    String? peculiarSRP,
    String? keynoteObservations,
  }) =>
      HomeopathyPeculiarSymptoms(
        peculiarSRP: peculiarSRP ?? this.peculiarSRP,
        keynoteObservations:
            keynoteObservations ?? this.keynoteObservations,
      );
}

/// N. Homeopathic Assessment (Totality, Repertorization & Prescription)
class HomeopathyPrescriptionNotes {
  final String repertorizationNotes;
  final String totalityOfSymptoms;
  final String miasmaticTendency;
  final String prescribedRemedy;
  final String differentialRemedies;
  final String potency;
  final String repetitionScale;
  final String adviceDiet;

  const HomeopathyPrescriptionNotes({
    this.repertorizationNotes = '',
    this.totalityOfSymptoms = '',
    this.miasmaticTendency = '',
    this.prescribedRemedy = '',
    this.differentialRemedies = '',
    this.potency = '',
    this.repetitionScale = '',
    this.adviceDiet = '',
  });

  bool get isCompleted => prescribedRemedy.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'repertorizationNotes': repertorizationNotes,
        'totalityOfSymptoms': totalityOfSymptoms,
        'miasmaticTendency': miasmaticTendency,
        'prescribedRemedy': prescribedRemedy,
        'differentialRemedies': differentialRemedies,
        'potency': potency,
        'repetitionScale': repetitionScale,
        'adviceDiet': adviceDiet,
      };

  factory HomeopathyPrescriptionNotes.fromMap(Map<String, dynamic> map) =>
      HomeopathyPrescriptionNotes(
        repertorizationNotes: map['repertorizationNotes'] as String? ?? '',
        totalityOfSymptoms: map['totalityOfSymptoms'] as String? ?? '',
        miasmaticTendency: map['miasmaticTendency'] as String? ?? '',
        prescribedRemedy: map['prescribedRemedy'] as String? ?? '',
        differentialRemedies: map['differentialRemedies'] as String? ?? '',
        potency: map['potency'] as String? ?? '',
        repetitionScale: map['repetitionScale'] as String? ?? '',
        adviceDiet: map['adviceDiet'] as String? ?? '',
      );

  HomeopathyPrescriptionNotes copyWith({
    String? repertorizationNotes,
    String? totalityOfSymptoms,
    String? miasmaticTendency,
    String? prescribedRemedy,
    String? differentialRemedies,
    String? potency,
    String? repetitionScale,
    String? adviceDiet,
  }) =>
      HomeopathyPrescriptionNotes(
        repertorizationNotes:
            repertorizationNotes ?? this.repertorizationNotes,
        totalityOfSymptoms: totalityOfSymptoms ?? this.totalityOfSymptoms,
        miasmaticTendency: miasmaticTendency ?? this.miasmaticTendency,
        prescribedRemedy: prescribedRemedy ?? this.prescribedRemedy,
        differentialRemedies:
            differentialRemedies ?? this.differentialRemedies,
        potency: potency ?? this.potency,
        repetitionScale: repetitionScale ?? this.repetitionScale,
        adviceDiet: adviceDiet ?? this.adviceDiet,
      );
}

/// O. Follow-Up & Second Prescription
class HomeopathyFollowUp {
  final String responseRating; // e.g. "Marked Improvement", "Moderate Improvement", "Same", "Aggravation", "New Symptoms"
  final String heringsLawDirection; // e.g. "Inside-outward", "Above-downward", "Reverse order of symptoms"
  final String clinicalChangesObserved;
  final String nextPrescriptionPlan; // e.g. "Continue Same (Sac Lac)", "Increase Potency", "Change Remedy"
  final DateTime? nextFollowUpDate;
  final String followUpNotes;

  const HomeopathyFollowUp({
    this.responseRating = '',
    this.heringsLawDirection = '',
    this.clinicalChangesObserved = '',
    this.nextPrescriptionPlan = '',
    this.nextFollowUpDate,
    this.followUpNotes = '',
  });

  bool get isCompleted =>
      responseRating.trim().isNotEmpty ||
      clinicalChangesObserved.trim().isNotEmpty ||
      nextPrescriptionPlan.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'responseRating': responseRating,
        'heringsLawDirection': heringsLawDirection,
        'clinicalChangesObserved': clinicalChangesObserved,
        'nextPrescriptionPlan': nextPrescriptionPlan,
        'nextFollowUpDate': nextFollowUpDate?.millisecondsSinceEpoch,
        'followUpNotes': followUpNotes,
      };

  factory HomeopathyFollowUp.fromMap(Map<String, dynamic> map) =>
      HomeopathyFollowUp(
        responseRating: map['responseRating'] as String? ?? '',
        heringsLawDirection: map['heringsLawDirection'] as String? ?? '',
        clinicalChangesObserved:
            map['clinicalChangesObserved'] as String? ?? '',
        nextPrescriptionPlan: map['nextPrescriptionPlan'] as String? ?? '',
        nextFollowUpDate: map['nextFollowUpDate'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (map['nextFollowUpDate'] as num).toInt())
            : null,
        followUpNotes: map['followUpNotes'] as String? ?? '',
      );

  HomeopathyFollowUp copyWith({
    String? responseRating,
    String? heringsLawDirection,
    String? clinicalChangesObserved,
    String? nextPrescriptionPlan,
    DateTime? nextFollowUpDate,
    String? followUpNotes,
  }) =>
      HomeopathyFollowUp(
        responseRating: responseRating ?? this.responseRating,
        heringsLawDirection: heringsLawDirection ?? this.heringsLawDirection,
        clinicalChangesObserved:
            clinicalChangesObserved ?? this.clinicalChangesObserved,
        nextPrescriptionPlan: nextPrescriptionPlan ?? this.nextPrescriptionPlan,
        nextFollowUpDate: nextFollowUpDate ?? this.nextFollowUpDate,
        followUpNotes: followUpNotes ?? this.followUpNotes,
      );
}

/// Root Homeopathy Case Sheet Model covering all clinical sections.
class HomeopathyCaseSheet {
  final String id;
  final String patientId;
  final String doctorId;
  final bool isCompleted;

  final HomeopathyCaseOverview overview;
  final HomeopathyChiefComplaint chiefComplaint;
  final HomeopathyModalities modalities;
  final HomeopathyGeneralSymptoms generalSymptoms;
  final HomeopathyPhysicalSymptoms physicalSymptoms;
  final HomeopathyFemaleHistory femaleReproductive;
  final HomeopathyMentalEmotional mentalEmotional;
  final HomeopathyDreamsSleep dreamsSleep;
  final HomeopathySexualHistory sexualHistory;
  final HomeopathyMedicalHistory medicalHistory;
  final HomeopathyPhysicalExam physicalExamination;
  final HomeopathyInvestigations investigations;
  final HomeopathyPeculiarSymptoms peculiarSymptoms;
  final HomeopathyPrescriptionNotes prescriptionNotes;
  final HomeopathyFollowUp followUp;
  final String additionalNotes;

  // --- Extended sections from PDF questionnaires ---
  final HomeopathyCaseSheetCategory caseSheetCategory;
  final HomeopathyChildhoodHistory childhoodHistory;
  final HomeopathyChildrenCaseSheet childrenCaseSheet;
  final HomeopathyFemaleEndocrine femaleEndocrine;
  final HomeopathyAcuteSheet acuteSheet;

  final DateTime createdAt;
  final DateTime updatedAt;
  final String syncStatus;

  const HomeopathyCaseSheet({
    required this.id,
    required this.patientId,
    required this.doctorId,
    this.isCompleted = false,
    required this.overview,
    required this.chiefComplaint,
    required this.modalities,
    required this.generalSymptoms,
    required this.physicalSymptoms,
    required this.femaleReproductive,
    required this.mentalEmotional,
    required this.dreamsSleep,
    required this.sexualHistory,
    required this.medicalHistory,
    required this.physicalExamination,
    required this.investigations,
    required this.peculiarSymptoms,
    required this.prescriptionNotes,
    this.followUp = const HomeopathyFollowUp(),
    this.additionalNotes = '',
    this.caseSheetCategory = HomeopathyCaseSheetCategory.general,
    this.childhoodHistory = const HomeopathyChildhoodHistory(),
    this.childrenCaseSheet = const HomeopathyChildrenCaseSheet(),
    this.femaleEndocrine = const HomeopathyFemaleEndocrine(),
    this.acuteSheet = const HomeopathyAcuteSheet(),
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = 'synced',
  });

  /// Counts how many of the core clinical sections have active data.
  int completedSectionsCount({bool isFemale = false}) {
    int count = 0;
    if (overview.isCompleted) count++;
    if (chiefComplaint.isCompleted) count++;
    if (modalities.isCompleted) count++;
    if (generalSymptoms.isCompleted) count++;
    if (physicalSymptoms.isCompleted) count++;
    if (isFemale && femaleReproductive.isCompleted) count++;
    if (mentalEmotional.isCompleted) count++;
    if (dreamsSleep.isCompleted) count++;
    if (sexualHistory.isCompleted) count++;
    if (medicalHistory.isCompleted) count++;
    if (physicalExamination.isCompleted) count++;
    if (investigations.isCompleted) count++;
    if (peculiarSymptoms.isCompleted) count++;
    if (prescriptionNotes.isCompleted) count++;
    if (followUp.isCompleted) count++;
    if (childhoodHistory.isCompleted) count++;
    if (category == HomeopathyCaseSheetCategory.children && childrenCaseSheet.isCompleted) count++;
    if (category == HomeopathyCaseSheetCategory.femaleEndocrine && femaleEndocrine.isCompleted) count++;
    if (category == HomeopathyCaseSheetCategory.acute && acuteSheet.isCompleted) count++;
    return count;
  }

  HomeopathyCaseSheetCategory get category => caseSheetCategory;

  int totalSectionsCount({bool isFemale = false}) {
    int base = isFemale ? 15 : 14;
    base++; // childhoodHistory
    if (caseSheetCategory == HomeopathyCaseSheetCategory.children) base++;
    if (caseSheetCategory == HomeopathyCaseSheetCategory.femaleEndocrine) base++;
    if (caseSheetCategory == HomeopathyCaseSheetCategory.acute) base++;
    return base;
  }

  factory HomeopathyCaseSheet.empty({
    required String id,
    required String patientId,
    required String doctorId,
  }) {
    final now = DateTime.now();
    return HomeopathyCaseSheet(
      id: id,
      patientId: patientId,
      doctorId: doctorId,
      isCompleted: false,
      overview: HomeopathyCaseOverview(caseDate: now),
      chiefComplaint: const HomeopathyChiefComplaint(),
      modalities: const HomeopathyModalities(),
      generalSymptoms: const HomeopathyGeneralSymptoms(),
      physicalSymptoms: const HomeopathyPhysicalSymptoms(),
      femaleReproductive: const HomeopathyFemaleHistory(),
      mentalEmotional: const HomeopathyMentalEmotional(),
      dreamsSleep: const HomeopathyDreamsSleep(),
      sexualHistory: const HomeopathySexualHistory(),
      medicalHistory: const HomeopathyMedicalHistory(),
      physicalExamination: const HomeopathyPhysicalExam(),
      investigations: const HomeopathyInvestigations(),
      peculiarSymptoms: const HomeopathyPeculiarSymptoms(),
      prescriptionNotes: const HomeopathyPrescriptionNotes(),
      followUp: const HomeopathyFollowUp(),
      additionalNotes: '',
      caseSheetCategory: HomeopathyCaseSheetCategory.general,
      childhoodHistory: const HomeopathyChildhoodHistory(),
      childrenCaseSheet: const HomeopathyChildrenCaseSheet(),
      femaleEndocrine: const HomeopathyFemaleEndocrine(),
      acuteSheet: const HomeopathyAcuteSheet(),
      createdAt: now,
      updatedAt: now,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'patientId': patientId,
        'doctorId': doctorId,
        'caseDate': overview.caseDate.millisecondsSinceEpoch,
        'caseType': overview.caseType.name,
        'isCompleted': isCompleted ? 1 : 0,
        'chiefProblem': overview.chiefProblem,
        'priority': overview.priority,
        'consultationReason': overview.consultationReason,
        'referralSource': overview.referralSource,
        'priorHomeopathyExperience': overview.priorHomeopathyExperience,
        'patientPerceivedCause': overview.patientPerceivedCause,
        'overview': jsonEncode(overview.toMap()),
        'chiefComplaint': jsonEncode(chiefComplaint.toMap()),
        'modalities': jsonEncode(modalities.toMap()),
        'generalSymptoms': jsonEncode(generalSymptoms.toMap()),
        'physicalSymptoms': jsonEncode(physicalSymptoms.toMap()),
        'femaleReproductive': jsonEncode(femaleReproductive.toMap()),
        'mentalEmotional': jsonEncode(mentalEmotional.toMap()),
        'dreamsSleep': jsonEncode(dreamsSleep.toMap()),
        'sexualHistory': jsonEncode(sexualHistory.toMap()),
        'medicalHistory': jsonEncode(medicalHistory.toMap()),
        'physicalExamination': jsonEncode(physicalExamination.toMap()),
        'investigations': jsonEncode(investigations.toMap()),
        'peculiarSymptoms': jsonEncode(peculiarSymptoms.toMap()),
        'prescriptionNotes': jsonEncode(prescriptionNotes.toMap()),
        'repertorizationNotes': prescriptionNotes.repertorizationNotes,
        'miasmaticTendency': prescriptionNotes.miasmaticTendency,
        'suggestedRemedies': prescriptionNotes.prescribedRemedy,
        'followUp': jsonEncode(followUp.toMap()),
        'additionalNotes': additionalNotes,
        'caseSheetCategory': caseSheetCategory.name,
        'childhoodHistory': jsonEncode(childhoodHistory.toMap()),
        'childrenCaseSheet': jsonEncode(childrenCaseSheet.toMap()),
        'femaleEndocrine': jsonEncode(femaleEndocrine.toMap()),
        'acuteSheet': jsonEncode(acuteSheet.toMap()),
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'syncStatus': syncStatus,
      };

  factory HomeopathyCaseSheet.fromMap(Map<String, dynamic> map, {String? id}) {
    Map<String, dynamic> parseSection(dynamic val) {
      if (val is Map<String, dynamic>) return val;
      if (val is String && val.trim().isNotEmpty && val != '{}') {
        try {
          final decoded = jsonDecode(val);
          if (decoded is Map<String, dynamic>) return decoded;
        } catch (_) {}
      }
      return <String, dynamic>{};
    }

    final sheetId = id ?? (map['id'] as String? ?? '');
    final dateMillis = (map['caseDate'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    final createdMillis = (map['createdAt'] as num?)?.toInt() ?? dateMillis;
    final updatedMillis = (map['updatedAt'] as num?)?.toInt() ?? dateMillis;

    final overviewMap = parseSection(map['overview']);
    final prescMap = parseSection(map['prescriptionNotes']);

    return HomeopathyCaseSheet(
      id: sheetId,
      patientId: map['patientId'] as String? ?? '',
      doctorId: map['doctorId'] as String? ?? '',
      isCompleted: (map['isCompleted'] as num?)?.toInt() == 1 ||
          map['isCompleted'] == true,
      overview: overviewMap.isNotEmpty
          ? HomeopathyCaseOverview.fromMap(overviewMap)
          : HomeopathyCaseOverview(
              caseType: HomeopathyCaseType.fromString(map['caseType'] as String?),
              caseDate: DateTime.fromMillisecondsSinceEpoch(dateMillis),
              chiefProblem: map['chiefProblem'] as String? ?? '',
              priority: map['priority'] as String? ?? 'normal',
              consultationReason: map['consultationReason'] as String? ?? '',
              referralSource: map['referralSource'] as String? ?? '',
              priorHomeopathyExperience:
                  map['priorHomeopathyExperience'] as String? ?? '',
              patientPerceivedCause: map['patientPerceivedCause'] as String? ?? '',
            ),
      chiefComplaint:
          HomeopathyChiefComplaint.fromMap(parseSection(map['chiefComplaint'])),
      modalities:
          HomeopathyModalities.fromMap(parseSection(map['modalities'])),
      generalSymptoms: HomeopathyGeneralSymptoms.fromMap(
          parseSection(map['generalSymptoms'])),
      physicalSymptoms: HomeopathyPhysicalSymptoms.fromMap(
          parseSection(map['physicalSymptoms'])),
      femaleReproductive: HomeopathyFemaleHistory.fromMap(
          parseSection(map['femaleReproductive'])),
      mentalEmotional: HomeopathyMentalEmotional.fromMap(
          parseSection(map['mentalEmotional'])),
      dreamsSleep:
          HomeopathyDreamsSleep.fromMap(parseSection(map['dreamsSleep'])),
      sexualHistory:
          HomeopathySexualHistory.fromMap(parseSection(map['sexualHistory'])),
      medicalHistory: HomeopathyMedicalHistory.fromMap(
          parseSection(map['medicalHistory'])),
      physicalExamination: HomeopathyPhysicalExam.fromMap(
          parseSection(map['physicalExamination'])),
      investigations:
          HomeopathyInvestigations.fromMap(parseSection(map['investigations'])),
      peculiarSymptoms: HomeopathyPeculiarSymptoms.fromMap(
          parseSection(map['peculiarSymptoms'])),
      prescriptionNotes: prescMap.isNotEmpty
          ? HomeopathyPrescriptionNotes.fromMap(prescMap)
          : HomeopathyPrescriptionNotes(
              repertorizationNotes: map['repertorizationNotes'] as String? ?? '',
              totalityOfSymptoms: map['totalityOfSymptoms'] as String? ?? '',
              miasmaticTendency: map['miasmaticTendency'] as String? ?? '',
              prescribedRemedy: map['suggestedRemedies'] as String? ??
                  (map['prescribedRemedy'] as String? ?? ''),
              differentialRemedies:
                  map['differentialRemedies'] as String? ?? '',
              potency: map['potency'] as String? ?? '',
              repetitionScale: map['repetitionScale'] as String? ?? '',
              adviceDiet: map['adviceDiet'] as String? ?? '',
            ),
      followUp: HomeopathyFollowUp.fromMap(parseSection(map['followUp'])),
      additionalNotes: map['additionalNotes'] as String? ?? '',
      caseSheetCategory: HomeopathyCaseSheetCategory.fromString(
          map['caseSheetCategory'] as String?),
      childhoodHistory: HomeopathyChildhoodHistory.fromMap(
          parseSection(map['childhoodHistory'])),
      childrenCaseSheet: HomeopathyChildrenCaseSheet.fromMap(
          parseSection(map['childrenCaseSheet'])),
      femaleEndocrine: HomeopathyFemaleEndocrine.fromMap(
          parseSection(map['femaleEndocrine'])),
      acuteSheet: HomeopathyAcuteSheet.fromMap(
          parseSection(map['acuteSheet'])),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdMillis),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedMillis),
      syncStatus: map['syncStatus'] as String? ?? 'synced',
    );
  }

  factory HomeopathyCaseSheet.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    return HomeopathyCaseSheet.fromMap(doc.data() ?? {}, id: doc.id);
  }

  HomeopathyCaseSheet copyWith({
    String? id,
    String? patientId,
    String? doctorId,
    bool? isCompleted,
    HomeopathyCaseOverview? overview,
    HomeopathyChiefComplaint? chiefComplaint,
    HomeopathyModalities? modalities,
    HomeopathyGeneralSymptoms? generalSymptoms,
    HomeopathyPhysicalSymptoms? physicalSymptoms,
    HomeopathyFemaleHistory? femaleReproductive,
    HomeopathyMentalEmotional? mentalEmotional,
    HomeopathyDreamsSleep? dreamsSleep,
    HomeopathySexualHistory? sexualHistory,
    HomeopathyMedicalHistory? medicalHistory,
    HomeopathyPhysicalExam? physicalExamination,
    HomeopathyInvestigations? investigations,
    HomeopathyPeculiarSymptoms? peculiarSymptoms,
    HomeopathyPrescriptionNotes? prescriptionNotes,
    HomeopathyFollowUp? followUp,
    String? additionalNotes,
    HomeopathyCaseSheetCategory? caseSheetCategory,
    HomeopathyChildhoodHistory? childhoodHistory,
    HomeopathyChildrenCaseSheet? childrenCaseSheet,
    HomeopathyFemaleEndocrine? femaleEndocrine,
    HomeopathyAcuteSheet? acuteSheet,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? syncStatus,
  }) =>
      HomeopathyCaseSheet(
        id: id ?? this.id,
        patientId: patientId ?? this.patientId,
        doctorId: doctorId ?? this.doctorId,
        isCompleted: isCompleted ?? this.isCompleted,
        overview: overview ?? this.overview,
        chiefComplaint: chiefComplaint ?? this.chiefComplaint,
        modalities: modalities ?? this.modalities,
        generalSymptoms: generalSymptoms ?? this.generalSymptoms,
        physicalSymptoms: physicalSymptoms ?? this.physicalSymptoms,
        femaleReproductive: femaleReproductive ?? this.femaleReproductive,
        mentalEmotional: mentalEmotional ?? this.mentalEmotional,
        dreamsSleep: dreamsSleep ?? this.dreamsSleep,
        sexualHistory: sexualHistory ?? this.sexualHistory,
        medicalHistory: medicalHistory ?? this.medicalHistory,
        physicalExamination: physicalExamination ?? this.physicalExamination,
        investigations: investigations ?? this.investigations,
        peculiarSymptoms: peculiarSymptoms ?? this.peculiarSymptoms,
        prescriptionNotes: prescriptionNotes ?? this.prescriptionNotes,
        followUp: followUp ?? this.followUp,
        additionalNotes: additionalNotes ?? this.additionalNotes,
        caseSheetCategory: caseSheetCategory ?? this.caseSheetCategory,
        childhoodHistory: childhoodHistory ?? this.childhoodHistory,
        childrenCaseSheet: childrenCaseSheet ?? this.childrenCaseSheet,
        femaleEndocrine: femaleEndocrine ?? this.femaleEndocrine,
        acuteSheet: acuteSheet ?? this.acuteSheet,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
      );
}
