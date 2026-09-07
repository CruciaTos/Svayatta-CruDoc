/// Extended homeopathy case sheet sections for specialized questionnaire types.
///
/// Contains:
/// - [HomeopathyCaseSheetCategory] — Selector for which case form to use.
/// - [HomeopathyChildhoodHistory] — Childhood nature, habits, fears (General Q25).
/// - [HomeopathyChildrenCaseSheet] — Full pediatric questionnaire (27 questions).
/// - [HomeopathyFemaleEndocrine] — Female & Endocrine/Thyroid questionnaire.
/// - [HomeopathyAcuteSheet] — Short-form acute presentation questionnaire.
library;

/// Which questionnaire template to use for this case.
enum HomeopathyCaseSheetCategory {
  general,
  children,
  femaleEndocrine,
  acute;

  static HomeopathyCaseSheetCategory fromString(String? val) {
    if (val == null) return HomeopathyCaseSheetCategory.general;
    final lower = val.toLowerCase().trim();
    if (lower == 'children') return HomeopathyCaseSheetCategory.children;
    if (lower == 'femaleendocrine' || lower == 'female_endocrine') {
      return HomeopathyCaseSheetCategory.femaleEndocrine;
    }
    if (lower == 'acute') return HomeopathyCaseSheetCategory.acute;
    return HomeopathyCaseSheetCategory.general;
  }

  String get label {
    switch (this) {
      case HomeopathyCaseSheetCategory.general:
        return 'General Case Sheet';
      case HomeopathyCaseSheetCategory.children:
        return 'Children Case Sheet';
      case HomeopathyCaseSheetCategory.femaleEndocrine:
        return 'Female & Endocrine';
      case HomeopathyCaseSheetCategory.acute:
        return 'Acute Case Sheet';
    }
  }
}

// ---------------------------------------------------------------------------
// Childhood History (General Case Sheet — Q25)
// ---------------------------------------------------------------------------

/// Childhood history section for the General Case Sheet (Q25).
/// Captures nature, habits, fears, dreams, relationships, and sensitivities
/// from the patient's childhood — important for constitutional analysis.
class HomeopathyChildhoodHistory {
  final String childhoodNature;
  final String childhoodHabits;
  final String childhoodFears;
  final String childhoodDreams;
  final String childhoodRelationships;
  final String childhoodSensitivities;

  const HomeopathyChildhoodHistory({
    this.childhoodNature = '',
    this.childhoodHabits = '',
    this.childhoodFears = '',
    this.childhoodDreams = '',
    this.childhoodRelationships = '',
    this.childhoodSensitivities = '',
  });

  bool get isCompleted =>
      childhoodNature.trim().isNotEmpty ||
      childhoodFears.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'childhoodNature': childhoodNature,
        'childhoodHabits': childhoodHabits,
        'childhoodFears': childhoodFears,
        'childhoodDreams': childhoodDreams,
        'childhoodRelationships': childhoodRelationships,
        'childhoodSensitivities': childhoodSensitivities,
      };

  factory HomeopathyChildhoodHistory.fromMap(Map<String, dynamic> map) =>
      HomeopathyChildhoodHistory(
        childhoodNature: map['childhoodNature'] as String? ?? '',
        childhoodHabits: map['childhoodHabits'] as String? ?? '',
        childhoodFears: map['childhoodFears'] as String? ?? '',
        childhoodDreams: map['childhoodDreams'] as String? ?? '',
        childhoodRelationships:
            map['childhoodRelationships'] as String? ?? '',
        childhoodSensitivities:
            map['childhoodSensitivities'] as String? ?? '',
      );

  HomeopathyChildhoodHistory copyWith({
    String? childhoodNature,
    String? childhoodHabits,
    String? childhoodFears,
    String? childhoodDreams,
    String? childhoodRelationships,
    String? childhoodSensitivities,
  }) =>
      HomeopathyChildhoodHistory(
        childhoodNature: childhoodNature ?? this.childhoodNature,
        childhoodHabits: childhoodHabits ?? this.childhoodHabits,
        childhoodFears: childhoodFears ?? this.childhoodFears,
        childhoodDreams: childhoodDreams ?? this.childhoodDreams,
        childhoodRelationships:
            childhoodRelationships ?? this.childhoodRelationships,
        childhoodSensitivities:
            childhoodSensitivities ?? this.childhoodSensitivities,
      );
}

// ---------------------------------------------------------------------------
// Children Case Sheet (Pediatric — 27 questions)
// ---------------------------------------------------------------------------

/// Full pediatric case-taking questionnaire.
/// Contains all 27 questions from the Children Case Sheet PDF, plus
/// organ-by-organ sections.
class HomeopathyChildrenCaseSheet {
  // Temperament & Behavior
  final String coldOrHeatSensitive; // Q3
  final String behaviorWhenUpset; // Q4
  final String whatMakesHappy; // Q5
  final String schoolBehavior; // Q6 — school, friends, elders, youngers, teachers
  final int graspingIntelligenceScore; // Q7 — 1 to 10
  final String childTypeDescription; // Q8 — mild/arrogant/rude/cunning/etc.

  // Health & Medical
  final String vaccinationHistory; // Q9
  final String favoriteSportActivity; // Q10
  final String attitudeToParents; // Q11
  final String childMedicalHistory; // Q12
  final String maturityLevel; // Q13 — independence, possessive/generous
  final String familyProblemsReaction; // Q14
  final String childIntrovertExtrovert; // Q15
  final String independenceLevel; // Q16

  // Physical generals
  final String dailyWaterIntake; // Q17 — litres, appetite, bowels, sweat
  final String birthComplications; // Q18
  final String motherPregnancyHistory; // Q19
  final String motherMedicalHistory; // Q20
  final String familyHealthHereditary; // Q21
  final String walkingTeethingAge; // Q22
  final String abnormalBehaviors; // Q23

  // Psychology
  final String childFears; // Q24 — darkness, animals, exams, imaginary, etc.
  final String childSleepingHabits; // Q25 — posture, dreams, fears at sleep
  final String abnormalCravings; // Q26
  final String wormsProblems; // Q27

  // Organ-by-organ
  final String headSymptoms;
  final String eyeSymptoms;
  final String noseRespirationSymptoms;
  final String tongueMouthTeeth;
  final String throatSymptoms;
  final String coughAsthmaDetails;
  final String stomachSymptoms;
  final String extremitiesSymptoms;
  final String stoolRectumSymptoms;
  final String urinarySymptoms;
  final String sexualAwareness; // Q5 — age-appropriate awareness
  final String feverDetails;

  final String additionalChildInfo;

  const HomeopathyChildrenCaseSheet({
    this.coldOrHeatSensitive = '',
    this.behaviorWhenUpset = '',
    this.whatMakesHappy = '',
    this.schoolBehavior = '',
    this.graspingIntelligenceScore = 0,
    this.childTypeDescription = '',
    this.vaccinationHistory = '',
    this.favoriteSportActivity = '',
    this.attitudeToParents = '',
    this.childMedicalHistory = '',
    this.maturityLevel = '',
    this.familyProblemsReaction = '',
    this.childIntrovertExtrovert = '',
    this.independenceLevel = '',
    this.dailyWaterIntake = '',
    this.birthComplications = '',
    this.motherPregnancyHistory = '',
    this.motherMedicalHistory = '',
    this.familyHealthHereditary = '',
    this.walkingTeethingAge = '',
    this.abnormalBehaviors = '',
    this.childFears = '',
    this.childSleepingHabits = '',
    this.abnormalCravings = '',
    this.wormsProblems = '',
    this.headSymptoms = '',
    this.eyeSymptoms = '',
    this.noseRespirationSymptoms = '',
    this.tongueMouthTeeth = '',
    this.throatSymptoms = '',
    this.coughAsthmaDetails = '',
    this.stomachSymptoms = '',
    this.extremitiesSymptoms = '',
    this.stoolRectumSymptoms = '',
    this.urinarySymptoms = '',
    this.sexualAwareness = '',
    this.feverDetails = '',
    this.additionalChildInfo = '',
  });

  bool get isCompleted =>
      coldOrHeatSensitive.trim().isNotEmpty ||
      schoolBehavior.trim().isNotEmpty ||
      childTypeDescription.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'coldOrHeatSensitive': coldOrHeatSensitive,
        'behaviorWhenUpset': behaviorWhenUpset,
        'whatMakesHappy': whatMakesHappy,
        'schoolBehavior': schoolBehavior,
        'graspingIntelligenceScore': graspingIntelligenceScore,
        'childTypeDescription': childTypeDescription,
        'vaccinationHistory': vaccinationHistory,
        'favoriteSportActivity': favoriteSportActivity,
        'attitudeToParents': attitudeToParents,
        'childMedicalHistory': childMedicalHistory,
        'maturityLevel': maturityLevel,
        'familyProblemsReaction': familyProblemsReaction,
        'childIntrovertExtrovert': childIntrovertExtrovert,
        'independenceLevel': independenceLevel,
        'dailyWaterIntake': dailyWaterIntake,
        'birthComplications': birthComplications,
        'motherPregnancyHistory': motherPregnancyHistory,
        'motherMedicalHistory': motherMedicalHistory,
        'familyHealthHereditary': familyHealthHereditary,
        'walkingTeethingAge': walkingTeethingAge,
        'abnormalBehaviors': abnormalBehaviors,
        'childFears': childFears,
        'childSleepingHabits': childSleepingHabits,
        'abnormalCravings': abnormalCravings,
        'wormsProblems': wormsProblems,
        'headSymptoms': headSymptoms,
        'eyeSymptoms': eyeSymptoms,
        'noseRespirationSymptoms': noseRespirationSymptoms,
        'tongueMouthTeeth': tongueMouthTeeth,
        'throatSymptoms': throatSymptoms,
        'coughAsthmaDetails': coughAsthmaDetails,
        'stomachSymptoms': stomachSymptoms,
        'extremitiesSymptoms': extremitiesSymptoms,
        'stoolRectumSymptoms': stoolRectumSymptoms,
        'urinarySymptoms': urinarySymptoms,
        'sexualAwareness': sexualAwareness,
        'feverDetails': feverDetails,
        'additionalChildInfo': additionalChildInfo,
      };

  factory HomeopathyChildrenCaseSheet.fromMap(Map<String, dynamic> map) =>
      HomeopathyChildrenCaseSheet(
        coldOrHeatSensitive: map['coldOrHeatSensitive'] as String? ?? '',
        behaviorWhenUpset: map['behaviorWhenUpset'] as String? ?? '',
        whatMakesHappy: map['whatMakesHappy'] as String? ?? '',
        schoolBehavior: map['schoolBehavior'] as String? ?? '',
        graspingIntelligenceScore:
            (map['graspingIntelligenceScore'] as num?)?.toInt() ?? 0,
        childTypeDescription: map['childTypeDescription'] as String? ?? '',
        vaccinationHistory: map['vaccinationHistory'] as String? ?? '',
        favoriteSportActivity: map['favoriteSportActivity'] as String? ?? '',
        attitudeToParents: map['attitudeToParents'] as String? ?? '',
        childMedicalHistory: map['childMedicalHistory'] as String? ?? '',
        maturityLevel: map['maturityLevel'] as String? ?? '',
        familyProblemsReaction:
            map['familyProblemsReaction'] as String? ?? '',
        childIntrovertExtrovert:
            map['childIntrovertExtrovert'] as String? ?? '',
        independenceLevel: map['independenceLevel'] as String? ?? '',
        dailyWaterIntake: map['dailyWaterIntake'] as String? ?? '',
        birthComplications: map['birthComplications'] as String? ?? '',
        motherPregnancyHistory:
            map['motherPregnancyHistory'] as String? ?? '',
        motherMedicalHistory: map['motherMedicalHistory'] as String? ?? '',
        familyHealthHereditary:
            map['familyHealthHereditary'] as String? ?? '',
        walkingTeethingAge: map['walkingTeethingAge'] as String? ?? '',
        abnormalBehaviors: map['abnormalBehaviors'] as String? ?? '',
        childFears: map['childFears'] as String? ?? '',
        childSleepingHabits: map['childSleepingHabits'] as String? ?? '',
        abnormalCravings: map['abnormalCravings'] as String? ?? '',
        wormsProblems: map['wormsProblems'] as String? ?? '',
        headSymptoms: map['headSymptoms'] as String? ?? '',
        eyeSymptoms: map['eyeSymptoms'] as String? ?? '',
        noseRespirationSymptoms:
            map['noseRespirationSymptoms'] as String? ?? '',
        tongueMouthTeeth: map['tongueMouthTeeth'] as String? ?? '',
        throatSymptoms: map['throatSymptoms'] as String? ?? '',
        coughAsthmaDetails: map['coughAsthmaDetails'] as String? ?? '',
        stomachSymptoms: map['stomachSymptoms'] as String? ?? '',
        extremitiesSymptoms: map['extremitiesSymptoms'] as String? ?? '',
        stoolRectumSymptoms: map['stoolRectumSymptoms'] as String? ?? '',
        urinarySymptoms: map['urinarySymptoms'] as String? ?? '',
        sexualAwareness: map['sexualAwareness'] as String? ?? '',
        feverDetails: map['feverDetails'] as String? ?? '',
        additionalChildInfo: map['additionalChildInfo'] as String? ?? '',
      );

  HomeopathyChildrenCaseSheet copyWith({
    String? coldOrHeatSensitive,
    String? behaviorWhenUpset,
    String? whatMakesHappy,
    String? schoolBehavior,
    int? graspingIntelligenceScore,
    String? childTypeDescription,
    String? vaccinationHistory,
    String? favoriteSportActivity,
    String? attitudeToParents,
    String? childMedicalHistory,
    String? maturityLevel,
    String? familyProblemsReaction,
    String? childIntrovertExtrovert,
    String? independenceLevel,
    String? dailyWaterIntake,
    String? birthComplications,
    String? motherPregnancyHistory,
    String? motherMedicalHistory,
    String? familyHealthHereditary,
    String? walkingTeethingAge,
    String? abnormalBehaviors,
    String? childFears,
    String? childSleepingHabits,
    String? abnormalCravings,
    String? wormsProblems,
    String? headSymptoms,
    String? eyeSymptoms,
    String? noseRespirationSymptoms,
    String? tongueMouthTeeth,
    String? throatSymptoms,
    String? coughAsthmaDetails,
    String? stomachSymptoms,
    String? extremitiesSymptoms,
    String? stoolRectumSymptoms,
    String? urinarySymptoms,
    String? sexualAwareness,
    String? feverDetails,
    String? additionalChildInfo,
  }) =>
      HomeopathyChildrenCaseSheet(
        coldOrHeatSensitive:
            coldOrHeatSensitive ?? this.coldOrHeatSensitive,
        behaviorWhenUpset: behaviorWhenUpset ?? this.behaviorWhenUpset,
        whatMakesHappy: whatMakesHappy ?? this.whatMakesHappy,
        schoolBehavior: schoolBehavior ?? this.schoolBehavior,
        graspingIntelligenceScore:
            graspingIntelligenceScore ?? this.graspingIntelligenceScore,
        childTypeDescription:
            childTypeDescription ?? this.childTypeDescription,
        vaccinationHistory: vaccinationHistory ?? this.vaccinationHistory,
        favoriteSportActivity:
            favoriteSportActivity ?? this.favoriteSportActivity,
        attitudeToParents: attitudeToParents ?? this.attitudeToParents,
        childMedicalHistory:
            childMedicalHistory ?? this.childMedicalHistory,
        maturityLevel: maturityLevel ?? this.maturityLevel,
        familyProblemsReaction:
            familyProblemsReaction ?? this.familyProblemsReaction,
        childIntrovertExtrovert:
            childIntrovertExtrovert ?? this.childIntrovertExtrovert,
        independenceLevel: independenceLevel ?? this.independenceLevel,
        dailyWaterIntake: dailyWaterIntake ?? this.dailyWaterIntake,
        birthComplications: birthComplications ?? this.birthComplications,
        motherPregnancyHistory:
            motherPregnancyHistory ?? this.motherPregnancyHistory,
        motherMedicalHistory:
            motherMedicalHistory ?? this.motherMedicalHistory,
        familyHealthHereditary:
            familyHealthHereditary ?? this.familyHealthHereditary,
        walkingTeethingAge: walkingTeethingAge ?? this.walkingTeethingAge,
        abnormalBehaviors: abnormalBehaviors ?? this.abnormalBehaviors,
        childFears: childFears ?? this.childFears,
        childSleepingHabits:
            childSleepingHabits ?? this.childSleepingHabits,
        abnormalCravings: abnormalCravings ?? this.abnormalCravings,
        wormsProblems: wormsProblems ?? this.wormsProblems,
        headSymptoms: headSymptoms ?? this.headSymptoms,
        eyeSymptoms: eyeSymptoms ?? this.eyeSymptoms,
        noseRespirationSymptoms:
            noseRespirationSymptoms ?? this.noseRespirationSymptoms,
        tongueMouthTeeth: tongueMouthTeeth ?? this.tongueMouthTeeth,
        throatSymptoms: throatSymptoms ?? this.throatSymptoms,
        coughAsthmaDetails:
            coughAsthmaDetails ?? this.coughAsthmaDetails,
        stomachSymptoms: stomachSymptoms ?? this.stomachSymptoms,
        extremitiesSymptoms:
            extremitiesSymptoms ?? this.extremitiesSymptoms,
        stoolRectumSymptoms:
            stoolRectumSymptoms ?? this.stoolRectumSymptoms,
        urinarySymptoms: urinarySymptoms ?? this.urinarySymptoms,
        sexualAwareness: sexualAwareness ?? this.sexualAwareness,
        feverDetails: feverDetails ?? this.feverDetails,
        additionalChildInfo:
            additionalChildInfo ?? this.additionalChildInfo,
      );
}

// ---------------------------------------------------------------------------
// Female & Endocrine Diseases Case Sheet
// ---------------------------------------------------------------------------

/// Case sheet for Female & Endocrine Diseases (thyroid, hormonal, lifecycle).
/// Covers disease manifestation, endocrine triggers, organ details,
/// glands, skin, cardiac, and stages of life.
class HomeopathyFemaleEndocrine {
  // Core
  final String medicalDiagnosis;
  final String howAndWhenStarted;
  final String physiologicalCauseTrigger; // menarche, pregnancy, OC pills, etc.
  final String emotionalTriggers;

  // Disease manifestation
  final String diseaseManifestationLocation; // thyroid: general, myxoedema, goitre, exophthalmos
  final String otherOrgansInvolved;
  final String goitreDetails;

  // Organ-by-organ (specific to this form)
  final String endocrineHeadSymptoms;
  final String endocrineEyeSymptoms;
  final String endocrineNoseRespiration;
  final String endocrineTongueMouthTeeth;
  final String endocrineThroatSymptoms;
  final String endocrineCoughAsthma;
  final String endocrineStomachSymptoms;
  final String endocrineExtremities;
  final String endocrineStoolRectum;

  // System-wise
  final String sensationSymptoms;
  final String gastrointestinalSymptoms;
  final String respiratorySymptoms;
  final String cardiacCirculatorySymptoms;
  final String glandsProblems;
  final String skinSymptoms;
  final String rheumatologySymptoms;
  final String cnsSymptoms;
  final String faceEntProblems;
  final String physicalWeakness;

  // History
  final String familyDiseaseHistory;
  final String personalMedicalHistory;

  // Stages of life
  final String stagesOfLife; // childhood/puberty/pregnancy/post-parturition/menopause/etc.
  final String menstrualHistory;

  // Relationships
  final String relationshipDetails; // family/spouse/children/in-laws/colleagues/tensions

  const HomeopathyFemaleEndocrine({
    this.medicalDiagnosis = '',
    this.howAndWhenStarted = '',
    this.physiologicalCauseTrigger = '',
    this.emotionalTriggers = '',
    this.diseaseManifestationLocation = '',
    this.otherOrgansInvolved = '',
    this.goitreDetails = '',
    this.endocrineHeadSymptoms = '',
    this.endocrineEyeSymptoms = '',
    this.endocrineNoseRespiration = '',
    this.endocrineTongueMouthTeeth = '',
    this.endocrineThroatSymptoms = '',
    this.endocrineCoughAsthma = '',
    this.endocrineStomachSymptoms = '',
    this.endocrineExtremities = '',
    this.endocrineStoolRectum = '',
    this.sensationSymptoms = '',
    this.gastrointestinalSymptoms = '',
    this.respiratorySymptoms = '',
    this.cardiacCirculatorySymptoms = '',
    this.glandsProblems = '',
    this.skinSymptoms = '',
    this.rheumatologySymptoms = '',
    this.cnsSymptoms = '',
    this.faceEntProblems = '',
    this.physicalWeakness = '',
    this.familyDiseaseHistory = '',
    this.personalMedicalHistory = '',
    this.stagesOfLife = '',
    this.menstrualHistory = '',
    this.relationshipDetails = '',
  });

  bool get isCompleted =>
      medicalDiagnosis.trim().isNotEmpty ||
      physiologicalCauseTrigger.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'medicalDiagnosis': medicalDiagnosis,
        'howAndWhenStarted': howAndWhenStarted,
        'physiologicalCauseTrigger': physiologicalCauseTrigger,
        'emotionalTriggers': emotionalTriggers,
        'diseaseManifestationLocation': diseaseManifestationLocation,
        'otherOrgansInvolved': otherOrgansInvolved,
        'goitreDetails': goitreDetails,
        'endocrineHeadSymptoms': endocrineHeadSymptoms,
        'endocrineEyeSymptoms': endocrineEyeSymptoms,
        'endocrineNoseRespiration': endocrineNoseRespiration,
        'endocrineTongueMouthTeeth': endocrineTongueMouthTeeth,
        'endocrineThroatSymptoms': endocrineThroatSymptoms,
        'endocrineCoughAsthma': endocrineCoughAsthma,
        'endocrineStomachSymptoms': endocrineStomachSymptoms,
        'endocrineExtremities': endocrineExtremities,
        'endocrineStoolRectum': endocrineStoolRectum,
        'sensationSymptoms': sensationSymptoms,
        'gastrointestinalSymptoms': gastrointestinalSymptoms,
        'respiratorySymptoms': respiratorySymptoms,
        'cardiacCirculatorySymptoms': cardiacCirculatorySymptoms,
        'glandsProblems': glandsProblems,
        'skinSymptoms': skinSymptoms,
        'rheumatologySymptoms': rheumatologySymptoms,
        'cnsSymptoms': cnsSymptoms,
        'faceEntProblems': faceEntProblems,
        'physicalWeakness': physicalWeakness,
        'familyDiseaseHistory': familyDiseaseHistory,
        'personalMedicalHistory': personalMedicalHistory,
        'stagesOfLife': stagesOfLife,
        'menstrualHistory': menstrualHistory,
        'relationshipDetails': relationshipDetails,
      };

  factory HomeopathyFemaleEndocrine.fromMap(Map<String, dynamic> map) =>
      HomeopathyFemaleEndocrine(
        medicalDiagnosis: map['medicalDiagnosis'] as String? ?? '',
        howAndWhenStarted: map['howAndWhenStarted'] as String? ?? '',
        physiologicalCauseTrigger:
            map['physiologicalCauseTrigger'] as String? ?? '',
        emotionalTriggers: map['emotionalTriggers'] as String? ?? '',
        diseaseManifestationLocation:
            map['diseaseManifestationLocation'] as String? ?? '',
        otherOrgansInvolved: map['otherOrgansInvolved'] as String? ?? '',
        goitreDetails: map['goitreDetails'] as String? ?? '',
        endocrineHeadSymptoms:
            map['endocrineHeadSymptoms'] as String? ?? '',
        endocrineEyeSymptoms:
            map['endocrineEyeSymptoms'] as String? ?? '',
        endocrineNoseRespiration:
            map['endocrineNoseRespiration'] as String? ?? '',
        endocrineTongueMouthTeeth:
            map['endocrineTongueMouthTeeth'] as String? ?? '',
        endocrineThroatSymptoms:
            map['endocrineThroatSymptoms'] as String? ?? '',
        endocrineCoughAsthma:
            map['endocrineCoughAsthma'] as String? ?? '',
        endocrineStomachSymptoms:
            map['endocrineStomachSymptoms'] as String? ?? '',
        endocrineExtremities:
            map['endocrineExtremities'] as String? ?? '',
        endocrineStoolRectum:
            map['endocrineStoolRectum'] as String? ?? '',
        sensationSymptoms: map['sensationSymptoms'] as String? ?? '',
        gastrointestinalSymptoms:
            map['gastrointestinalSymptoms'] as String? ?? '',
        respiratorySymptoms: map['respiratorySymptoms'] as String? ?? '',
        cardiacCirculatorySymptoms:
            map['cardiacCirculatorySymptoms'] as String? ?? '',
        glandsProblems: map['glandsProblems'] as String? ?? '',
        skinSymptoms: map['skinSymptoms'] as String? ?? '',
        rheumatologySymptoms:
            map['rheumatologySymptoms'] as String? ?? '',
        cnsSymptoms: map['cnsSymptoms'] as String? ?? '',
        faceEntProblems: map['faceEntProblems'] as String? ?? '',
        physicalWeakness: map['physicalWeakness'] as String? ?? '',
        familyDiseaseHistory:
            map['familyDiseaseHistory'] as String? ?? '',
        personalMedicalHistory:
            map['personalMedicalHistory'] as String? ?? '',
        stagesOfLife: map['stagesOfLife'] as String? ?? '',
        menstrualHistory: map['menstrualHistory'] as String? ?? '',
        relationshipDetails: map['relationshipDetails'] as String? ?? '',
      );

  HomeopathyFemaleEndocrine copyWith({
    String? medicalDiagnosis,
    String? howAndWhenStarted,
    String? physiologicalCauseTrigger,
    String? emotionalTriggers,
    String? diseaseManifestationLocation,
    String? otherOrgansInvolved,
    String? goitreDetails,
    String? endocrineHeadSymptoms,
    String? endocrineEyeSymptoms,
    String? endocrineNoseRespiration,
    String? endocrineTongueMouthTeeth,
    String? endocrineThroatSymptoms,
    String? endocrineCoughAsthma,
    String? endocrineStomachSymptoms,
    String? endocrineExtremities,
    String? endocrineStoolRectum,
    String? sensationSymptoms,
    String? gastrointestinalSymptoms,
    String? respiratorySymptoms,
    String? cardiacCirculatorySymptoms,
    String? glandsProblems,
    String? skinSymptoms,
    String? rheumatologySymptoms,
    String? cnsSymptoms,
    String? faceEntProblems,
    String? physicalWeakness,
    String? familyDiseaseHistory,
    String? personalMedicalHistory,
    String? stagesOfLife,
    String? menstrualHistory,
    String? relationshipDetails,
  }) =>
      HomeopathyFemaleEndocrine(
        medicalDiagnosis: medicalDiagnosis ?? this.medicalDiagnosis,
        howAndWhenStarted: howAndWhenStarted ?? this.howAndWhenStarted,
        physiologicalCauseTrigger:
            physiologicalCauseTrigger ?? this.physiologicalCauseTrigger,
        emotionalTriggers: emotionalTriggers ?? this.emotionalTriggers,
        diseaseManifestationLocation: diseaseManifestationLocation ??
            this.diseaseManifestationLocation,
        otherOrgansInvolved:
            otherOrgansInvolved ?? this.otherOrgansInvolved,
        goitreDetails: goitreDetails ?? this.goitreDetails,
        endocrineHeadSymptoms:
            endocrineHeadSymptoms ?? this.endocrineHeadSymptoms,
        endocrineEyeSymptoms:
            endocrineEyeSymptoms ?? this.endocrineEyeSymptoms,
        endocrineNoseRespiration:
            endocrineNoseRespiration ?? this.endocrineNoseRespiration,
        endocrineTongueMouthTeeth:
            endocrineTongueMouthTeeth ?? this.endocrineTongueMouthTeeth,
        endocrineThroatSymptoms:
            endocrineThroatSymptoms ?? this.endocrineThroatSymptoms,
        endocrineCoughAsthma:
            endocrineCoughAsthma ?? this.endocrineCoughAsthma,
        endocrineStomachSymptoms:
            endocrineStomachSymptoms ?? this.endocrineStomachSymptoms,
        endocrineExtremities:
            endocrineExtremities ?? this.endocrineExtremities,
        endocrineStoolRectum:
            endocrineStoolRectum ?? this.endocrineStoolRectum,
        sensationSymptoms: sensationSymptoms ?? this.sensationSymptoms,
        gastrointestinalSymptoms:
            gastrointestinalSymptoms ?? this.gastrointestinalSymptoms,
        respiratorySymptoms:
            respiratorySymptoms ?? this.respiratorySymptoms,
        cardiacCirculatorySymptoms: cardiacCirculatorySymptoms ??
            this.cardiacCirculatorySymptoms,
        glandsProblems: glandsProblems ?? this.glandsProblems,
        skinSymptoms: skinSymptoms ?? this.skinSymptoms,
        rheumatologySymptoms:
            rheumatologySymptoms ?? this.rheumatologySymptoms,
        cnsSymptoms: cnsSymptoms ?? this.cnsSymptoms,
        faceEntProblems: faceEntProblems ?? this.faceEntProblems,
        physicalWeakness: physicalWeakness ?? this.physicalWeakness,
        familyDiseaseHistory:
            familyDiseaseHistory ?? this.familyDiseaseHistory,
        personalMedicalHistory:
            personalMedicalHistory ?? this.personalMedicalHistory,
        stagesOfLife: stagesOfLife ?? this.stagesOfLife,
        menstrualHistory: menstrualHistory ?? this.menstrualHistory,
        relationshipDetails:
            relationshipDetails ?? this.relationshipDetails,
      );
}

// ---------------------------------------------------------------------------
// Acute Case Sheet (Chandra Homeocare style — 22 questions + tables)
// ---------------------------------------------------------------------------

/// Short-form acute case-taking questionnaire.
/// Designed for quick acute presentations (fever, cold, cough, diarrhea, etc.).
class HomeopathyAcuteSheet {
  final String howKnewAboutUs; // Q1
  final String priorHomeopathyUse; // Q2
  final String detailedComplaint; // Q3 — fever/chills/cold/cough/pains/etc.
  final String causeOfComplaint; // Q4 — emotional or physical
  final String otherProblems; // Q5
  final String whatMakesWorse; // Q6
  final String whatMakesBetter; // Q7
  final String mentalConditionDuringSuffering; // Q8
  final String appetiteCravingsAversions; // Q9
  final String waterRequirement; // Q10 — less/normal/heavy
  final String sweatDetails; // Q11 — area, odour
  final String postureModalities; // Q12 — better/worse
  final String sleepStoolUrination; // Q13
  final String overallHealthHistory; // Q14
  final String acuteFeverDetails; // Q15 — how/when, chill/heat/sweat stages
  final String specialUncommonSymptoms; // Q16
  final String coughRespirationDetail; // Q17
  final String additionalCoughInfo; // Q18
  final String looseDryCoughDetails; // Q19 — taste, posture
  final String diarrheaConstipationDetails; // Q20
  final String bodyPainDetails; // Q21
  final String additionalInfo; // Q22

  // Quick-reference table data (JSON-serialized)
  final String chiefComplaintTable; // Time/Temperature/Sleep/Air/Thirst/Taste/Eating/Sleep modalities
  final String thirstMensesSleepTable; // Thirst/Menses/Sleep/Heat-Cold/Stool/Urination/Appetite/Cravings/Aversions
  final String stateOfMindTable; // Reaction to disease/company/time/fears/dreams/facial expression

  const HomeopathyAcuteSheet({
    this.howKnewAboutUs = '',
    this.priorHomeopathyUse = '',
    this.detailedComplaint = '',
    this.causeOfComplaint = '',
    this.otherProblems = '',
    this.whatMakesWorse = '',
    this.whatMakesBetter = '',
    this.mentalConditionDuringSuffering = '',
    this.appetiteCravingsAversions = '',
    this.waterRequirement = '',
    this.sweatDetails = '',
    this.postureModalities = '',
    this.sleepStoolUrination = '',
    this.overallHealthHistory = '',
    this.acuteFeverDetails = '',
    this.specialUncommonSymptoms = '',
    this.coughRespirationDetail = '',
    this.additionalCoughInfo = '',
    this.looseDryCoughDetails = '',
    this.diarrheaConstipationDetails = '',
    this.bodyPainDetails = '',
    this.additionalInfo = '',
    this.chiefComplaintTable = '',
    this.thirstMensesSleepTable = '',
    this.stateOfMindTable = '',
  });

  bool get isCompleted =>
      detailedComplaint.trim().isNotEmpty ||
      causeOfComplaint.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'howKnewAboutUs': howKnewAboutUs,
        'priorHomeopathyUse': priorHomeopathyUse,
        'detailedComplaint': detailedComplaint,
        'causeOfComplaint': causeOfComplaint,
        'otherProblems': otherProblems,
        'whatMakesWorse': whatMakesWorse,
        'whatMakesBetter': whatMakesBetter,
        'mentalConditionDuringSuffering': mentalConditionDuringSuffering,
        'appetiteCravingsAversions': appetiteCravingsAversions,
        'waterRequirement': waterRequirement,
        'sweatDetails': sweatDetails,
        'postureModalities': postureModalities,
        'sleepStoolUrination': sleepStoolUrination,
        'overallHealthHistory': overallHealthHistory,
        'acuteFeverDetails': acuteFeverDetails,
        'specialUncommonSymptoms': specialUncommonSymptoms,
        'coughRespirationDetail': coughRespirationDetail,
        'additionalCoughInfo': additionalCoughInfo,
        'looseDryCoughDetails': looseDryCoughDetails,
        'diarrheaConstipationDetails': diarrheaConstipationDetails,
        'bodyPainDetails': bodyPainDetails,
        'additionalInfo': additionalInfo,
        'chiefComplaintTable': chiefComplaintTable,
        'thirstMensesSleepTable': thirstMensesSleepTable,
        'stateOfMindTable': stateOfMindTable,
      };

  factory HomeopathyAcuteSheet.fromMap(Map<String, dynamic> map) =>
      HomeopathyAcuteSheet(
        howKnewAboutUs: map['howKnewAboutUs'] as String? ?? '',
        priorHomeopathyUse: map['priorHomeopathyUse'] as String? ?? '',
        detailedComplaint: map['detailedComplaint'] as String? ?? '',
        causeOfComplaint: map['causeOfComplaint'] as String? ?? '',
        otherProblems: map['otherProblems'] as String? ?? '',
        whatMakesWorse: map['whatMakesWorse'] as String? ?? '',
        whatMakesBetter: map['whatMakesBetter'] as String? ?? '',
        mentalConditionDuringSuffering:
            map['mentalConditionDuringSuffering'] as String? ?? '',
        appetiteCravingsAversions:
            map['appetiteCravingsAversions'] as String? ?? '',
        waterRequirement: map['waterRequirement'] as String? ?? '',
        sweatDetails: map['sweatDetails'] as String? ?? '',
        postureModalities: map['postureModalities'] as String? ?? '',
        sleepStoolUrination: map['sleepStoolUrination'] as String? ?? '',
        overallHealthHistory:
            map['overallHealthHistory'] as String? ?? '',
        acuteFeverDetails: map['acuteFeverDetails'] as String? ?? '',
        specialUncommonSymptoms:
            map['specialUncommonSymptoms'] as String? ?? '',
        coughRespirationDetail:
            map['coughRespirationDetail'] as String? ?? '',
        additionalCoughInfo: map['additionalCoughInfo'] as String? ?? '',
        looseDryCoughDetails:
            map['looseDryCoughDetails'] as String? ?? '',
        diarrheaConstipationDetails:
            map['diarrheaConstipationDetails'] as String? ?? '',
        bodyPainDetails: map['bodyPainDetails'] as String? ?? '',
        additionalInfo: map['additionalInfo'] as String? ?? '',
        chiefComplaintTable: map['chiefComplaintTable'] as String? ?? '',
        thirstMensesSleepTable:
            map['thirstMensesSleepTable'] as String? ?? '',
        stateOfMindTable: map['stateOfMindTable'] as String? ?? '',
      );

  HomeopathyAcuteSheet copyWith({
    String? howKnewAboutUs,
    String? priorHomeopathyUse,
    String? detailedComplaint,
    String? causeOfComplaint,
    String? otherProblems,
    String? whatMakesWorse,
    String? whatMakesBetter,
    String? mentalConditionDuringSuffering,
    String? appetiteCravingsAversions,
    String? waterRequirement,
    String? sweatDetails,
    String? postureModalities,
    String? sleepStoolUrination,
    String? overallHealthHistory,
    String? acuteFeverDetails,
    String? specialUncommonSymptoms,
    String? coughRespirationDetail,
    String? additionalCoughInfo,
    String? looseDryCoughDetails,
    String? diarrheaConstipationDetails,
    String? bodyPainDetails,
    String? additionalInfo,
    String? chiefComplaintTable,
    String? thirstMensesSleepTable,
    String? stateOfMindTable,
  }) =>
      HomeopathyAcuteSheet(
        howKnewAboutUs: howKnewAboutUs ?? this.howKnewAboutUs,
        priorHomeopathyUse:
            priorHomeopathyUse ?? this.priorHomeopathyUse,
        detailedComplaint: detailedComplaint ?? this.detailedComplaint,
        causeOfComplaint: causeOfComplaint ?? this.causeOfComplaint,
        otherProblems: otherProblems ?? this.otherProblems,
        whatMakesWorse: whatMakesWorse ?? this.whatMakesWorse,
        whatMakesBetter: whatMakesBetter ?? this.whatMakesBetter,
        mentalConditionDuringSuffering: mentalConditionDuringSuffering ??
            this.mentalConditionDuringSuffering,
        appetiteCravingsAversions:
            appetiteCravingsAversions ?? this.appetiteCravingsAversions,
        waterRequirement: waterRequirement ?? this.waterRequirement,
        sweatDetails: sweatDetails ?? this.sweatDetails,
        postureModalities: postureModalities ?? this.postureModalities,
        sleepStoolUrination:
            sleepStoolUrination ?? this.sleepStoolUrination,
        overallHealthHistory:
            overallHealthHistory ?? this.overallHealthHistory,
        acuteFeverDetails: acuteFeverDetails ?? this.acuteFeverDetails,
        specialUncommonSymptoms:
            specialUncommonSymptoms ?? this.specialUncommonSymptoms,
        coughRespirationDetail:
            coughRespirationDetail ?? this.coughRespirationDetail,
        additionalCoughInfo:
            additionalCoughInfo ?? this.additionalCoughInfo,
        looseDryCoughDetails:
            looseDryCoughDetails ?? this.looseDryCoughDetails,
        diarrheaConstipationDetails: diarrheaConstipationDetails ??
            this.diarrheaConstipationDetails,
        bodyPainDetails: bodyPainDetails ?? this.bodyPainDetails,
        additionalInfo: additionalInfo ?? this.additionalInfo,
        chiefComplaintTable:
            chiefComplaintTable ?? this.chiefComplaintTable,
        thirstMensesSleepTable:
            thirstMensesSleepTable ?? this.thirstMensesSleepTable,
        stateOfMindTable: stateOfMindTable ?? this.stateOfMindTable,
      );
}
