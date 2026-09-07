import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:doctor_management_app/core/theme/app_colors.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/data/providers/homeopathy_providers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_form_helpers.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_extended_form_sections.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_voice_dictation_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/presentation/widgets/homeopathy_voice_scribe_modal.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';

/// Interactive mobile-first Homeopathy Case Taking Sheet.
class HomeopathyCaseTakingSheet extends ConsumerStatefulWidget {
  final Patient patient;
  final HomeopathyCaseSheet? initialCaseSheet;

  const HomeopathyCaseTakingSheet({
    super.key,
    required this.patient,
    this.initialCaseSheet,
  });

  static Future<bool?> show(
    BuildContext context, {
    required Patient patient,
    HomeopathyCaseSheet? initialCaseSheet,
  }) {
    return Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => HomeopathyCaseTakingSheet(
          patient: patient,
          initialCaseSheet: initialCaseSheet,
        ),
      ),
    );
  }

  @override
  ConsumerState<HomeopathyCaseTakingSheet> createState() =>
      _HomeopathyCaseTakingSheetState();
}

class _HomeopathyCaseTakingSheetState
    extends ConsumerState<HomeopathyCaseTakingSheet> {
  late HomeopathyCaseSheet _sheet;
  late HomeopathyCaseSheetCategory _category;
  late final ExtendedCaseSheetControllers _extCtrl;
  bool _isSaving = false;
  bool _sexualHistoryUnlocked = false;

  // Controllers for Section A: Overview
  late final TextEditingController _chiefProblemCtrl;
  late final TextEditingController _consultationReasonCtrl;
  late final TextEditingController _referralSourceCtrl;
  late final TextEditingController _priorHomeoExpCtrl;
  late final TextEditingController _perceivedCauseCtrl;

  // Controllers for Section B: Chief Complaint
  late final TextEditingController _complaintCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _sensationCtrl;
  late final TextEditingController _onsetCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _frequencyCtrl;
  late final TextEditingController _progressionCtrl;
  late final TextEditingController _triggeringCausesCtrl;
  late final TextEditingController _associatedSymptomsCtrl;

  // Controllers for Section C: Modalities
  late final TextEditingController _aggravatingCtrl;
  late final TextEditingController _amelioratingCtrl;
  late final TextEditingController _timePatternsCtrl;
  late final TextEditingController _positionCtrl;
  late final TextEditingController _motionCtrl;
  late final TextEditingController _temperatureWeatherCtrl;
  late final TextEditingController _foodDrinkModalitiesCtrl;
  late final TextEditingController _otherTriggersCtrl;

  // Controllers for Section D: Generals
  late final TextEditingController _appetiteCtrl;
  late final TextEditingController _thirstCtrl;
  late final TextEditingController _thirstStyleCtrl;
  late final TextEditingController _stoolsCtrl;
  late final TextEditingController _urineCtrl;
  late final TextEditingController _skinCtrl;
  late final TextEditingController _perspirationCtrl;
  late final TextEditingController _perspLocationCtrl;
  late final TextEditingController _perspOdourCtrl;
  late final TextEditingController _energyCtrl;

  // Controllers for Section E: Physicals
  late final TextEditingController _rheumatologyCtrl;
  late final TextEditingController _cnsCtrl;
  late final TextEditingController _faceEntCtrl;
  late final TextEditingController _headVertigoCtrl;
  late final TextEditingController _respiratoryCtrl;
  late final TextEditingController _feverChillCtrl;
  late final TextEditingController _feverHeatCtrl;
  late final TextEditingController _feverSweatCtrl;
  late final TextEditingController _feverPeriodicityCtrl;
  late final TextEditingController _coughTypeCtrl;
  late final TextEditingController _sputumDetailsCtrl;
  late final TextEditingController _coughTasteCtrl;
  late final TextEditingController _digestiveStoolCtrl;
  late final TextEditingController _painCharCtrl;
  late final TextEditingController _painLocCtrl;
  late final TextEditingController _painModCtrl;

  // Controllers for Section F: Female
  late final TextEditingController _mensesCycleCtrl;
  late final TextEditingController _mensesDurationCtrl;
  late final TextEditingController _flowCharCtrl;
  late final TextEditingController _menopauseCtrl;
  late final TextEditingController _suppressionCtrl;
  late final TextEditingController _leucorrhoeaCtrl;
  late final TextEditingController _obstetricCtrl;

  // Controllers for Section G: Mind & Emotions
  late final TextEditingController _dispositionCtrl;
  late final TextEditingController _anxietyCtrl;
  late final TextEditingController _companySolitudeCtrl;
  late final TextEditingController _consolationCtrl;
  late final TextEditingController _emotionalTriggersCtrl;
  late final TextEditingController _timeMoodCtrl;
  late final TextEditingController _behavioralCtrl;
  late final TextEditingController _reactionToDiseaseCtrl;
  late final TextEditingController _dullnessRestlessCtrl;
  late final TextEditingController _facialExpressionCtrl;
  late final TextEditingController _mentalShiftCtrl;
  late final TextEditingController _familyDynamicsCtrl;
  late final TextEditingController _spouseRelCtrl;
  late final TextEditingController _childrenRelCtrl;
  late final TextEditingController _inlawsRelCtrl;
  late final TextEditingController _colleaguesCtrl;
  late final TextEditingController _majorTensionsCtrl;

  // Controllers for Section H: Dreams & Sleep
  late final TextEditingController _sleepQualityCtrl;
  late final TextEditingController _sleepDisturbancesCtrl;
  late final TextEditingController _dreamCharCtrl;

  // Controllers for Section I: Sexual History
  late final TextEditingController _desireLevelCtrl;
  late final TextEditingController _sexualConcernsCtrl;
  late final TextEditingController _sexualNotesCtrl;

  // Controllers for Section J: Medical History
  late final TextEditingController _pastIllnessesCtrl;
  late final TextEditingController _surgeriesCtrl;
  late final TextEditingController _medicationsCtrl;
  late final TextEditingController _allergiesCtrl;
  late final TextEditingController _vaccinationCtrl;
  late final TextEditingController _familyHistoryCtrl;

  // Controllers for Section K: Physical Exam
  late final TextEditingController _constitutionCtrl;
  late final TextEditingController _tongueExamCtrl;
  late final TextEditingController _pulseBpCtrl;
  late final TextEditingController _sensitiveAreasCtrl;
  late final TextEditingController _clinicalObservationsCtrl;

  // Controllers for Section L: Investigations
  late final TextEditingController _labReportsCtrl;
  late final TextEditingController _imagingNotesCtrl;

  // Controllers for Section M: Peculiar SRP Symptoms
  late final TextEditingController _peculiarSrpCtrl;
  late final TextEditingController _keynoteObsCtrl;

  // Controllers for Section N: Prescription & Repertory
  late final TextEditingController _repertoryNotesCtrl;
  late final TextEditingController _totalityRubricsCtrl;
  late final TextEditingController _miasmCtrl;
  late final TextEditingController _remedyCtrl;
  late final TextEditingController _differentialRemediesCtrl;
  late final TextEditingController _potencyCtrl;
  late final TextEditingController _repetitionCtrl;
  late final TextEditingController _adviceDietCtrl;
  late final TextEditingController _additionalNotesCtrl;

  // Controllers for Section O: Follow-Up
  late final TextEditingController _followUpResponseCtrl;
  late final TextEditingController _heringsLawCtrl;
  late final TextEditingController _clinicalChangesCtrl;
  late final TextEditingController _nextPrescriptionPlanCtrl;
  late final TextEditingController _followUpNotesCtrl;
  DateTime? _nextFollowUpDate;

  bool get _isPatientFemale =>
      widget.patient.gender.toLowerCase().trim() == 'female';

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCaseSheet ??
        HomeopathyCaseSheet.empty(
          id: '',
          patientId: widget.patient.id,
          doctorId: widget.patient.doctorId,
        );
    _sheet = initial;
    _category = initial.caseSheetCategory;
    _extCtrl = ExtendedCaseSheetControllers.fromSheet(initial);

    // Initialize controllers
    _chiefProblemCtrl =
        TextEditingController(text: initial.overview.chiefProblem);
    _consultationReasonCtrl =
        TextEditingController(text: initial.overview.consultationReason);
    _referralSourceCtrl =
        TextEditingController(text: initial.overview.referralSource);
    _priorHomeoExpCtrl =
        TextEditingController(text: initial.overview.priorHomeopathyExperience);
    _perceivedCauseCtrl =
        TextEditingController(text: initial.overview.patientPerceivedCause);

    _complaintCtrl =
        TextEditingController(text: initial.chiefComplaint.complaint);
    _locationCtrl =
        TextEditingController(text: initial.chiefComplaint.location);
    _sensationCtrl = TextEditingController(
        text: initial.chiefComplaint.sensationDescription);
    _onsetCtrl = TextEditingController(text: initial.chiefComplaint.onset);
    _durationCtrl =
        TextEditingController(text: initial.chiefComplaint.duration);
    _frequencyCtrl =
        TextEditingController(text: initial.chiefComplaint.frequency);
    _progressionCtrl =
        TextEditingController(text: initial.chiefComplaint.progression);
    _triggeringCausesCtrl =
        TextEditingController(text: initial.chiefComplaint.triggeringCauses);
    _associatedSymptomsCtrl =
        TextEditingController(text: initial.chiefComplaint.associatedSymptoms);

    _aggravatingCtrl =
        TextEditingController(text: initial.modalities.aggravatingFactors);
    _amelioratingCtrl =
        TextEditingController(text: initial.modalities.amelioratingFactors);
    _timePatternsCtrl =
        TextEditingController(text: initial.modalities.timePatterns);
    _positionCtrl =
        TextEditingController(text: initial.modalities.positionModalities);
    _motionCtrl =
        TextEditingController(text: initial.modalities.motionModalities);
    _temperatureWeatherCtrl =
        TextEditingController(text: initial.modalities.temperatureWeather);
    _foodDrinkModalitiesCtrl =
        TextEditingController(text: initial.modalities.foodDrinkModalities);
    _otherTriggersCtrl =
        TextEditingController(text: initial.modalities.otherTriggers);

    _appetiteCtrl =
        TextEditingController(text: initial.generalSymptoms.appetite);
    _thirstCtrl = TextEditingController(text: initial.generalSymptoms.thirst);
    _thirstStyleCtrl =
        TextEditingController(text: initial.generalSymptoms.thirstStyle);
    _stoolsCtrl = TextEditingController(text: initial.generalSymptoms.stools);
    _urineCtrl = TextEditingController(text: initial.generalSymptoms.urine);
    _skinCtrl = TextEditingController(text: initial.generalSymptoms.skinState);
    _perspirationCtrl =
        TextEditingController(text: initial.generalSymptoms.perspiration);
    _perspLocationCtrl =
        TextEditingController(text: initial.generalSymptoms.perspirationLocation);
    _perspOdourCtrl =
        TextEditingController(text: initial.generalSymptoms.perspirationOdour);
    _energyCtrl =
        TextEditingController(text: initial.generalSymptoms.energyWeakness);

    _rheumatologyCtrl =
        TextEditingController(text: initial.physicalSymptoms.rheumatologyJoints);
    _cnsCtrl = TextEditingController(text: initial.physicalSymptoms.cnsNervous);
    _faceEntCtrl =
        TextEditingController(text: initial.physicalSymptoms.faceEnt);
    _headVertigoCtrl =
        TextEditingController(text: initial.physicalSymptoms.headVertigoSymptoms);
    _respiratoryCtrl =
        TextEditingController(text: initial.physicalSymptoms.respiratory);
    _feverChillCtrl = TextEditingController(
        text: initial.physicalSymptoms.thermoregulationFever.isNotEmpty
            ? initial.physicalSymptoms.thermoregulationFever
            : initial.physicalSymptoms.feverChillStage);
    _feverHeatCtrl =
        TextEditingController(text: initial.physicalSymptoms.feverHeatStage);
    _feverSweatCtrl =
        TextEditingController(text: initial.physicalSymptoms.feverSweatStage);
    _feverPeriodicityCtrl =
        TextEditingController(text: initial.physicalSymptoms.feverPeriodicity);
    _coughTypeCtrl =
        TextEditingController(text: initial.physicalSymptoms.coughType);
    _sputumDetailsCtrl =
        TextEditingController(text: initial.physicalSymptoms.sputumDetails);
    _coughTasteCtrl =
        TextEditingController(text: initial.physicalSymptoms.coughTasteInMouth);
    _digestiveStoolCtrl =
        TextEditingController(text: initial.physicalSymptoms.digestiveStoolDetails);
    _painCharCtrl = TextEditingController(
        text: initial.physicalSymptoms.painCharacteristics);
    _painLocCtrl =
        TextEditingController(text: initial.physicalSymptoms.painLocation);
    _painModCtrl =
        TextEditingController(text: initial.physicalSymptoms.painModalities);

    _mensesCycleCtrl =
        TextEditingController(text: initial.femaleReproductive.mensesCycle);
    _mensesDurationCtrl =
        TextEditingController(text: initial.femaleReproductive.mensesDuration);
    _flowCharCtrl =
        TextEditingController(text: initial.femaleReproductive.flowCharacter);
    _menopauseCtrl =
        TextEditingController(text: initial.femaleReproductive.menopauseDetails);
    _suppressionCtrl = TextEditingController(
        text: initial.femaleReproductive.menstrualSuppressionEffects);
    _leucorrhoeaCtrl = TextEditingController(
        text: initial.femaleReproductive.leucorrhoeaDetails);
    _obstetricCtrl = TextEditingController(
        text: initial.femaleReproductive.obstetricHistory);

    _dispositionCtrl =
        TextEditingController(text: initial.mentalEmotional.disposition);
    _anxietyCtrl =
        TextEditingController(text: initial.mentalEmotional.anxietyTriggers);
    _companySolitudeCtrl =
        TextEditingController(text: initial.mentalEmotional.companyVsSolitude);
    _consolationCtrl = TextEditingController(
        text: initial.mentalEmotional.reactionToConsolation);
    _emotionalTriggersCtrl =
        TextEditingController(text: initial.mentalEmotional.emotionalAetiology);
    _timeMoodCtrl =
        TextEditingController(text: initial.mentalEmotional.timeOfDayMood);
    _behavioralCtrl =
        TextEditingController(text: initial.mentalEmotional.behavioralChanges);
    _reactionToDiseaseCtrl =
        TextEditingController(text: initial.mentalEmotional.reactionToDisease);
    _dullnessRestlessCtrl =
        TextEditingController(text: initial.mentalEmotional.dullnessVsRestlessness);
    _facialExpressionCtrl =
        TextEditingController(text: initial.mentalEmotional.facialExpression);
    _mentalShiftCtrl =
        TextEditingController(text: initial.mentalEmotional.mentalShiftSinceIllness);
    _familyDynamicsCtrl =
        TextEditingController(text: initial.mentalEmotional.familyDynamics);
    _spouseRelCtrl =
        TextEditingController(text: initial.mentalEmotional.spouseRelationship);
    _childrenRelCtrl =
        TextEditingController(text: initial.mentalEmotional.childrenRelationship);
    _inlawsRelCtrl =
        TextEditingController(text: initial.mentalEmotional.inlawsRelationship);
    _colleaguesCtrl =
        TextEditingController(text: initial.mentalEmotional.colleaguesWorkStress);
    _majorTensionsCtrl =
        TextEditingController(text: initial.mentalEmotional.majorTensions);

    _sleepQualityCtrl =
        TextEditingController(text: initial.dreamsSleep.sleepQuality);
    _sleepDisturbancesCtrl =
        TextEditingController(text: initial.dreamsSleep.sleepDisturbances);
    _dreamCharCtrl =
        TextEditingController(text: initial.dreamsSleep.dreamCharacteristics);

    _desireLevelCtrl =
        TextEditingController(text: initial.sexualHistory.desireLevel);
    _sexualConcernsCtrl =
        TextEditingController(text: initial.sexualHistory.complaintsConcerns);
    _sexualNotesCtrl =
        TextEditingController(text: initial.sexualHistory.notes);

    _pastIllnessesCtrl =
        TextEditingController(text: initial.medicalHistory.pastIllnesses);
    _surgeriesCtrl =
        TextEditingController(text: initial.medicalHistory.surgicalHistory);
    _medicationsCtrl =
        TextEditingController(text: initial.medicalHistory.pastMedications);
    _allergiesCtrl =
        TextEditingController(text: initial.medicalHistory.allergies);
    _vaccinationCtrl =
        TextEditingController(text: initial.medicalHistory.vaccinationReactions);
    _familyHistoryCtrl =
        TextEditingController(text: initial.medicalHistory.familyHistory);

    _constitutionCtrl =
        TextEditingController(text: initial.physicalExamination.constitutionBuild);
    _tongueExamCtrl =
        TextEditingController(text: initial.physicalExamination.tongueExamination);
    _pulseBpCtrl =
        TextEditingController(text: initial.physicalExamination.nailsPulseBP);
    _sensitiveAreasCtrl =
        TextEditingController(text: initial.physicalExamination.sensitiveAreas);
    _clinicalObservationsCtrl = TextEditingController(
        text: initial.physicalExamination.clinicalObservations);

    _labReportsCtrl =
        TextEditingController(text: initial.investigations.labReports);
    _imagingNotesCtrl = TextEditingController(
        text: initial.investigations.imagingDiagnosticNotes);

    _peculiarSrpCtrl =
        TextEditingController(text: initial.peculiarSymptoms.peculiarSRP);
    _keynoteObsCtrl = TextEditingController(
        text: initial.peculiarSymptoms.keynoteObservations);

    _repertoryNotesCtrl = TextEditingController(
        text: initial.prescriptionNotes.repertorizationNotes);
    _totalityRubricsCtrl = TextEditingController(
        text: initial.prescriptionNotes.totalityOfSymptoms);
    _miasmCtrl = TextEditingController(
        text: initial.prescriptionNotes.miasmaticTendency);
    _remedyCtrl = TextEditingController(
        text: initial.prescriptionNotes.prescribedRemedy);
    _differentialRemediesCtrl = TextEditingController(
        text: initial.prescriptionNotes.differentialRemedies);
    _potencyCtrl =
        TextEditingController(text: initial.prescriptionNotes.potency);
    _repetitionCtrl =
        TextEditingController(text: initial.prescriptionNotes.repetitionScale);
    _adviceDietCtrl =
        TextEditingController(text: initial.prescriptionNotes.adviceDiet);

    _followUpResponseCtrl =
        TextEditingController(text: initial.followUp.responseRating);
    _heringsLawCtrl =
        TextEditingController(text: initial.followUp.heringsLawDirection);
    _clinicalChangesCtrl =
        TextEditingController(text: initial.followUp.clinicalChangesObserved);
    _nextPrescriptionPlanCtrl =
        TextEditingController(text: initial.followUp.nextPrescriptionPlan);
    _followUpNotesCtrl =
        TextEditingController(text: initial.followUp.followUpNotes);
    _nextFollowUpDate = initial.followUp.nextFollowUpDate;

    _additionalNotesCtrl =
        TextEditingController(text: initial.additionalNotes);
  }

  @override
  void dispose() {
    _chiefProblemCtrl.dispose();
    _consultationReasonCtrl.dispose();
    _referralSourceCtrl.dispose();
    _priorHomeoExpCtrl.dispose();
    _perceivedCauseCtrl.dispose();
    _complaintCtrl.dispose();
    _locationCtrl.dispose();
    _sensationCtrl.dispose();
    _onsetCtrl.dispose();
    _durationCtrl.dispose();
    _frequencyCtrl.dispose();
    _progressionCtrl.dispose();
    _triggeringCausesCtrl.dispose();
    _associatedSymptomsCtrl.dispose();
    _aggravatingCtrl.dispose();
    _amelioratingCtrl.dispose();
    _timePatternsCtrl.dispose();
    _positionCtrl.dispose();
    _motionCtrl.dispose();
    _temperatureWeatherCtrl.dispose();
    _foodDrinkModalitiesCtrl.dispose();
    _otherTriggersCtrl.dispose();
    _appetiteCtrl.dispose();
    _thirstCtrl.dispose();
    _thirstStyleCtrl.dispose();
    _stoolsCtrl.dispose();
    _urineCtrl.dispose();
    _skinCtrl.dispose();
    _perspirationCtrl.dispose();
    _perspLocationCtrl.dispose();
    _perspOdourCtrl.dispose();
    _energyCtrl.dispose();
    _rheumatologyCtrl.dispose();
    _cnsCtrl.dispose();
    _faceEntCtrl.dispose();
    _headVertigoCtrl.dispose();
    _respiratoryCtrl.dispose();
    _feverChillCtrl.dispose();
    _feverHeatCtrl.dispose();
    _feverSweatCtrl.dispose();
    _feverPeriodicityCtrl.dispose();
    _coughTypeCtrl.dispose();
    _sputumDetailsCtrl.dispose();
    _coughTasteCtrl.dispose();
    _digestiveStoolCtrl.dispose();
    _painCharCtrl.dispose();
    _painLocCtrl.dispose();
    _painModCtrl.dispose();
    _mensesCycleCtrl.dispose();
    _mensesDurationCtrl.dispose();
    _flowCharCtrl.dispose();
    _menopauseCtrl.dispose();
    _suppressionCtrl.dispose();
    _leucorrhoeaCtrl.dispose();
    _obstetricCtrl.dispose();
    _dispositionCtrl.dispose();
    _anxietyCtrl.dispose();
    _companySolitudeCtrl.dispose();
    _consolationCtrl.dispose();
    _emotionalTriggersCtrl.dispose();
    _timeMoodCtrl.dispose();
    _behavioralCtrl.dispose();
    _reactionToDiseaseCtrl.dispose();
    _dullnessRestlessCtrl.dispose();
    _facialExpressionCtrl.dispose();
    _mentalShiftCtrl.dispose();
    _familyDynamicsCtrl.dispose();
    _spouseRelCtrl.dispose();
    _childrenRelCtrl.dispose();
    _inlawsRelCtrl.dispose();
    _colleaguesCtrl.dispose();
    _majorTensionsCtrl.dispose();
    _sleepQualityCtrl.dispose();
    _sleepDisturbancesCtrl.dispose();
    _dreamCharCtrl.dispose();
    _desireLevelCtrl.dispose();
    _sexualConcernsCtrl.dispose();
    _sexualNotesCtrl.dispose();
    _pastIllnessesCtrl.dispose();
    _surgeriesCtrl.dispose();
    _medicationsCtrl.dispose();
    _allergiesCtrl.dispose();
    _vaccinationCtrl.dispose();
    _familyHistoryCtrl.dispose();
    _constitutionCtrl.dispose();
    _tongueExamCtrl.dispose();
    _pulseBpCtrl.dispose();
    _sensitiveAreasCtrl.dispose();
    _clinicalObservationsCtrl.dispose();
    _labReportsCtrl.dispose();
    _imagingNotesCtrl.dispose();
    _peculiarSrpCtrl.dispose();
    _keynoteObsCtrl.dispose();
    _repertoryNotesCtrl.dispose();
    _totalityRubricsCtrl.dispose();
    _miasmCtrl.dispose();
    _remedyCtrl.dispose();
    _differentialRemediesCtrl.dispose();
    _potencyCtrl.dispose();
    _repetitionCtrl.dispose();
    _adviceDietCtrl.dispose();
    _followUpResponseCtrl.dispose();
    _heringsLawCtrl.dispose();
    _clinicalChangesCtrl.dispose();
    _nextPrescriptionPlanCtrl.dispose();
    _followUpNotesCtrl.dispose();
    _additionalNotesCtrl.dispose();
    _extCtrl.dispose();
    super.dispose();
  }

  HomeopathyCaseSheet _buildSheetFromForm({required bool isCompleted}) {
    final genSymptoms = _extCtrl.updateGeneralSymptoms(
      _sheet.generalSymptoms.copyWith(
        appetite: _appetiteCtrl.text.trim(),
        thirst: _thirstCtrl.text.trim(),
        thirstStyle: _thirstStyleCtrl.text.trim(),
        stools: _stoolsCtrl.text.trim(),
        urine: _urineCtrl.text.trim(),
        skinState: _skinCtrl.text.trim(),
        perspiration: _perspirationCtrl.text.trim(),
        perspirationLocation: _perspLocationCtrl.text.trim(),
        perspirationOdour: _perspOdourCtrl.text.trim(),
        energyWeakness: _energyCtrl.text.trim(),
      ),
    );

    final mindSymptoms = _extCtrl.updateMentalEmotional(
      _sheet.mentalEmotional.copyWith(
        disposition: _dispositionCtrl.text.trim(),
        anxietyTriggers: _anxietyCtrl.text.trim(),
        companyVsSolitude: _companySolitudeCtrl.text.trim(),
        reactionToConsolation: _consolationCtrl.text.trim(),
        emotionalAetiology: _emotionalTriggersCtrl.text.trim(),
        timeOfDayMood: _timeMoodCtrl.text.trim(),
        behavioralChanges: _behavioralCtrl.text.trim(),
        reactionToDisease: _reactionToDiseaseCtrl.text.trim(),
        dullnessVsRestlessness: _dullnessRestlessCtrl.text.trim(),
        facialExpression: _facialExpressionCtrl.text.trim(),
        mentalShiftSinceIllness: _mentalShiftCtrl.text.trim(),
        familyDynamics: _familyDynamicsCtrl.text.trim(),
        spouseRelationship: _spouseRelCtrl.text.trim(),
        childrenRelationship: _childrenRelCtrl.text.trim(),
        inlawsRelationship: _inlawsRelCtrl.text.trim(),
        colleaguesWorkStress: _colleaguesCtrl.text.trim(),
        majorTensions: _majorTensionsCtrl.text.trim(),
      ),
    );

    final dreamsSymptoms = _extCtrl.updateDreamsSleep(
      _sheet.dreamsSleep.copyWith(
        sleepQuality: _sleepQualityCtrl.text.trim(),
        sleepDisturbances: _sleepDisturbancesCtrl.text.trim(),
        dreamCharacteristics: _dreamCharCtrl.text.trim(),
      ),
    );

    final childHist = _extCtrl.buildChildhoodHistory(_sheet.childhoodHistory);
    final pediaSheet = _extCtrl.buildChildrenCaseSheet(_sheet.childrenCaseSheet);
    final femEndo = _extCtrl.buildFemaleEndocrine(_sheet.femaleEndocrine);
    final acute = _extCtrl.buildAcuteSheet(_sheet.acuteSheet);

    return _sheet.copyWith(
      isCompleted: isCompleted,
      caseSheetCategory: _category,
      overview: _sheet.overview.copyWith(
        chiefProblem: _chiefProblemCtrl.text.trim(),
        consultationReason: _consultationReasonCtrl.text.trim(),
        referralSource: _referralSourceCtrl.text.trim(),
        priorHomeopathyExperience: _priorHomeoExpCtrl.text.trim(),
        patientPerceivedCause: _perceivedCauseCtrl.text.trim(),
      ),
      chiefComplaint: _sheet.chiefComplaint.copyWith(
        complaint: _complaintCtrl.text.trim(),
        location: _locationCtrl.text.trim(),
        sensationDescription: _sensationCtrl.text.trim(),
        onset: _onsetCtrl.text.trim(),
        duration: _durationCtrl.text.trim(),
        frequency: _frequencyCtrl.text.trim(),
        progression: _progressionCtrl.text.trim(),
        triggeringCauses: _triggeringCausesCtrl.text.trim(),
        associatedSymptoms: _associatedSymptomsCtrl.text.trim(),
      ),
      modalities: _sheet.modalities.copyWith(
        aggravatingFactors: _aggravatingCtrl.text.trim(),
        amelioratingFactors: _amelioratingCtrl.text.trim(),
        timePatterns: _timePatternsCtrl.text.trim(),
        positionModalities: _positionCtrl.text.trim(),
        motionModalities: _motionCtrl.text.trim(),
        temperatureWeather: _temperatureWeatherCtrl.text.trim(),
        foodDrinkModalities: _foodDrinkModalitiesCtrl.text.trim(),
        otherTriggers: _otherTriggersCtrl.text.trim(),
      ),
      generalSymptoms: genSymptoms,
      physicalSymptoms: _sheet.physicalSymptoms.copyWith(
        rheumatologyJoints: _rheumatologyCtrl.text.trim(),
        cnsNervous: _cnsCtrl.text.trim(),
        faceEnt: _faceEntCtrl.text.trim(),
        headVertigoSymptoms: _headVertigoCtrl.text.trim(),
        respiratory: _respiratoryCtrl.text.trim(),
        thermoregulationFever: _feverChillCtrl.text.trim(),
        feverChillStage: _feverChillCtrl.text.trim(),
        feverHeatStage: _feverHeatCtrl.text.trim(),
        feverSweatStage: _feverSweatCtrl.text.trim(),
        feverPeriodicity: _feverPeriodicityCtrl.text.trim(),
        coughType: _coughTypeCtrl.text.trim(),
        sputumDetails: _sputumDetailsCtrl.text.trim(),
        coughTasteInMouth: _coughTasteCtrl.text.trim(),
        digestiveStoolDetails: _digestiveStoolCtrl.text.trim(),
        painCharacteristics: _painCharCtrl.text.trim(),
        painLocation: _painLocCtrl.text.trim(),
        painModalities: _painModCtrl.text.trim(),
      ),
      femaleReproductive: _sheet.femaleReproductive.copyWith(
        mensesCycle: _mensesCycleCtrl.text.trim(),
        mensesDuration: _mensesDurationCtrl.text.trim(),
        flowCharacter: _flowCharCtrl.text.trim(),
        menopauseDetails: _menopauseCtrl.text.trim(),
        menstrualSuppressionEffects: _suppressionCtrl.text.trim(),
        leucorrhoeaDetails: _leucorrhoeaCtrl.text.trim(),
        obstetricHistory: _obstetricCtrl.text.trim(),
      ),
      mentalEmotional: mindSymptoms,
      dreamsSleep: dreamsSymptoms,
      childhoodHistory: childHist,
      childrenCaseSheet: pediaSheet,
      femaleEndocrine: femEndo,
      acuteSheet: acute,
      sexualHistory: _sheet.sexualHistory.copyWith(
        desireLevel: _desireLevelCtrl.text.trim(),
        complaintsConcerns: _sexualConcernsCtrl.text.trim(),
        notes: _sexualNotesCtrl.text.trim(),
      ),
      medicalHistory: _sheet.medicalHistory.copyWith(
        pastIllnesses: _pastIllnessesCtrl.text.trim(),
        surgicalHistory: _surgeriesCtrl.text.trim(),
        pastMedications: _medicationsCtrl.text.trim(),
        allergies: _allergiesCtrl.text.trim(),
        vaccinationReactions: _vaccinationCtrl.text.trim(),
        familyHistory: _familyHistoryCtrl.text.trim(),
      ),
      physicalExamination: _sheet.physicalExamination.copyWith(
        constitutionBuild: _constitutionCtrl.text.trim(),
        tongueExamination: _tongueExamCtrl.text.trim(),
        nailsPulseBP: _pulseBpCtrl.text.trim(),
        sensitiveAreas: _sensitiveAreasCtrl.text.trim(),
        clinicalObservations: _clinicalObservationsCtrl.text.trim(),
      ),
      investigations: _sheet.investigations.copyWith(
        labReports: _labReportsCtrl.text.trim(),
        imagingDiagnosticNotes: _imagingNotesCtrl.text.trim(),
      ),
      peculiarSymptoms: _sheet.peculiarSymptoms.copyWith(
        peculiarSRP: _peculiarSrpCtrl.text.trim(),
        keynoteObservations: _keynoteObsCtrl.text.trim(),
      ),
      prescriptionNotes: _sheet.prescriptionNotes.copyWith(
        repertorizationNotes: _repertoryNotesCtrl.text.trim(),
        totalityOfSymptoms: _totalityRubricsCtrl.text.trim(),
        miasmaticTendency: _miasmCtrl.text.trim(),
        prescribedRemedy: _remedyCtrl.text.trim(),
        differentialRemedies: _differentialRemediesCtrl.text.trim(),
        potency: _potencyCtrl.text.trim(),
        repetitionScale: _repetitionCtrl.text.trim(),
        adviceDiet: _adviceDietCtrl.text.trim(),
      ),
      followUp: _sheet.followUp.copyWith(
        responseRating: _followUpResponseCtrl.text.trim(),
        heringsLawDirection: _heringsLawCtrl.text.trim(),
        clinicalChangesObserved: _clinicalChangesCtrl.text.trim(),
        nextPrescriptionPlan: _nextPrescriptionPlanCtrl.text.trim(),
        nextFollowUpDate: _nextFollowUpDate,
        followUpNotes: _followUpNotesCtrl.text.trim(),
      ),
      additionalNotes: _additionalNotesCtrl.text.trim(),
    );
  }

  Future<void> _saveCase({required bool markComplete}) async {
    setState(() => _isSaving = true);
    try {
      final updated = _buildSheetFromForm(isCompleted: markComplete);
      await ref.read(homeopathyRepositoryProvider).saveCaseSheet(updated);
      ref.invalidate(homeopathyCaseSheetProvider(widget.patient.id));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.positiveGreen,
          content: Text(
            markComplete
                ? 'Case Sheet completed & saved successfully'
                : 'Case Sheet draft saved',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.negativeRed,
          content: Text('Failed to save case sheet: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _launchVoiceScribe() async {
    final updated = await HomeopathyVoiceScribeModal.show(
      context,
      existingSheet: _buildSheetFromForm(isCompleted: false),
    );

    if (updated != null && mounted) {
      setState(() {
        _sheet = updated;
        _populateControllersFromSheet(updated);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2E7D32),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Row(
            children: const [
              Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Case sheet populated from consultation voice recording! Review sections below.',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _populateControllersFromSheet(HomeopathyCaseSheet s) {
    _chiefProblemCtrl.text = s.overview.chiefProblem;
    _consultationReasonCtrl.text = s.overview.consultationReason;
    _referralSourceCtrl.text = s.overview.referralSource;
    _priorHomeoExpCtrl.text = s.overview.priorHomeopathyExperience;
    _perceivedCauseCtrl.text = s.overview.patientPerceivedCause;
    _complaintCtrl.text = s.chiefComplaint.complaint;
    _locationCtrl.text = s.chiefComplaint.location;
    _sensationCtrl.text = s.chiefComplaint.sensationDescription;
    _onsetCtrl.text = s.chiefComplaint.onset;
    _durationCtrl.text = s.chiefComplaint.duration;
    _frequencyCtrl.text = s.chiefComplaint.frequency;
    _progressionCtrl.text = s.chiefComplaint.progression;
    _triggeringCausesCtrl.text = s.chiefComplaint.triggeringCauses;
    _associatedSymptomsCtrl.text = s.chiefComplaint.associatedSymptoms;
    _aggravatingCtrl.text = s.modalities.aggravatingFactors;
    _amelioratingCtrl.text = s.modalities.amelioratingFactors;
    _timePatternsCtrl.text = s.modalities.timePatterns;
    _positionCtrl.text = s.modalities.positionModalities;
    _motionCtrl.text = s.modalities.motionModalities;
    _temperatureWeatherCtrl.text = s.modalities.temperatureWeather;
    _foodDrinkModalitiesCtrl.text = s.modalities.foodDrinkModalities;
    _otherTriggersCtrl.text = s.modalities.otherTriggers;
    _appetiteCtrl.text = s.generalSymptoms.appetite;
    _thirstCtrl.text = s.generalSymptoms.thirst;
    _thirstStyleCtrl.text = s.generalSymptoms.thirstStyle;
    _perspirationCtrl.text = s.generalSymptoms.perspiration;
    _perspLocationCtrl.text = s.generalSymptoms.perspirationLocation;
    _perspOdourCtrl.text = s.generalSymptoms.perspirationOdour;
    _stoolsCtrl.text = s.generalSymptoms.stools;
    _urineCtrl.text = s.generalSymptoms.urine;
    _skinCtrl.text = s.generalSymptoms.skinState;
    _energyCtrl.text = s.generalSymptoms.energyWeakness;
    _headVertigoCtrl.text = s.physicalSymptoms.headVertigoSymptoms;
    _respiratoryCtrl.text = s.physicalSymptoms.respiratory;
    _coughTypeCtrl.text = s.physicalSymptoms.coughType;
    _sputumDetailsCtrl.text = s.physicalSymptoms.sputumDetails;
    _coughTasteCtrl.text = s.physicalSymptoms.coughTasteInMouth;
    _feverChillCtrl.text = s.physicalSymptoms.feverChillStage;
    _feverHeatCtrl.text = s.physicalSymptoms.feverHeatStage;
    _feverSweatCtrl.text = s.physicalSymptoms.feverSweatStage;
    _feverPeriodicityCtrl.text = s.physicalSymptoms.feverPeriodicity;
    _digestiveStoolCtrl.text = s.physicalSymptoms.digestiveStoolDetails;
    _rheumatologyCtrl.text = s.physicalSymptoms.rheumatologyJoints;
    _cnsCtrl.text = s.physicalSymptoms.cnsNervous;
    _faceEntCtrl.text = s.physicalSymptoms.faceEnt;
    _painCharCtrl.text = s.physicalSymptoms.painCharacteristics;
    _painLocCtrl.text = s.physicalSymptoms.painLocation;
    _painModCtrl.text = s.physicalSymptoms.painModalities;
    _mensesCycleCtrl.text = s.femaleReproductive.mensesCycle;
    _mensesDurationCtrl.text = s.femaleReproductive.mensesDuration;
    _flowCharCtrl.text = s.femaleReproductive.flowCharacter;
    _menopauseCtrl.text = s.femaleReproductive.menopauseDetails;
    _suppressionCtrl.text = s.femaleReproductive.menstrualSuppressionEffects;
    _leucorrhoeaCtrl.text = s.femaleReproductive.leucorrhoeaDetails;
    _obstetricCtrl.text = s.femaleReproductive.obstetricHistory;
    _dispositionCtrl.text = s.mentalEmotional.disposition;
    _anxietyCtrl.text = s.mentalEmotional.anxietyTriggers;
    _companySolitudeCtrl.text = s.mentalEmotional.companyVsSolitude;
    _consolationCtrl.text = s.mentalEmotional.reactionToConsolation;
    _emotionalTriggersCtrl.text = s.mentalEmotional.emotionalAetiology;
    _reactionToDiseaseCtrl.text = s.mentalEmotional.reactionToDisease;
    _dullnessRestlessCtrl.text = s.mentalEmotional.dullnessVsRestlessness;
    _facialExpressionCtrl.text = s.mentalEmotional.facialExpression;
    _mentalShiftCtrl.text = s.mentalEmotional.mentalShiftSinceIllness;
    _familyDynamicsCtrl.text = s.mentalEmotional.familyDynamics;
    _spouseRelCtrl.text = s.mentalEmotional.spouseRelationship;
    _childrenRelCtrl.text = s.mentalEmotional.childrenRelationship;
    _inlawsRelCtrl.text = s.mentalEmotional.inlawsRelationship;
    _colleaguesCtrl.text = s.mentalEmotional.colleaguesWorkStress;
    _majorTensionsCtrl.text = s.mentalEmotional.majorTensions;
    _sleepQualityCtrl.text = s.dreamsSleep.sleepQuality;
    _sleepDisturbancesCtrl.text = s.dreamsSleep.sleepDisturbances;
    _dreamCharCtrl.text = s.dreamsSleep.dreamCharacteristics;
    _pastIllnessesCtrl.text = s.medicalHistory.pastIllnesses;
    _surgeriesCtrl.text = s.medicalHistory.surgicalHistory;
    _medicationsCtrl.text = s.medicalHistory.pastMedications;
    _allergiesCtrl.text = s.medicalHistory.allergies;
    _vaccinationCtrl.text = s.medicalHistory.vaccinationReactions;
    _familyHistoryCtrl.text = s.medicalHistory.familyHistory;
    _constitutionCtrl.text = s.physicalExamination.constitutionBuild;
    _tongueExamCtrl.text = s.physicalExamination.tongueExamination;
    _pulseBpCtrl.text = s.physicalExamination.nailsPulseBP;
    _sensitiveAreasCtrl.text = s.physicalExamination.sensitiveAreas;
    _clinicalObservationsCtrl.text = s.physicalExamination.clinicalObservations;
    _labReportsCtrl.text = s.investigations.labReports;
    _imagingNotesCtrl.text = s.investigations.imagingDiagnosticNotes;
    _peculiarSrpCtrl.text = s.peculiarSymptoms.peculiarSRP;
    _keynoteObsCtrl.text = s.peculiarSymptoms.keynoteObservations;
    _repertoryNotesCtrl.text = s.prescriptionNotes.repertorizationNotes;
    _totalityRubricsCtrl.text = s.prescriptionNotes.totalityOfSymptoms;
    _miasmCtrl.text = s.prescriptionNotes.miasmaticTendency;
    _remedyCtrl.text = s.prescriptionNotes.prescribedRemedy;
    _differentialRemediesCtrl.text = s.prescriptionNotes.differentialRemedies;
    _potencyCtrl.text = s.prescriptionNotes.potency;
    _repetitionCtrl.text = s.prescriptionNotes.repetitionScale;
    _adviceDietCtrl.text = s.prescriptionNotes.adviceDiet;
    _followUpResponseCtrl.text = s.followUp.responseRating;
    _heringsLawCtrl.text = s.followUp.heringsLawDirection;
    _clinicalChangesCtrl.text = s.followUp.clinicalChangesObserved;
    _nextPrescriptionPlanCtrl.text = s.followUp.nextPrescriptionPlan;
    _followUpNotesCtrl.text = s.followUp.followUpNotes;
    _nextFollowUpDate = s.followUp.nextFollowUpDate;
    _additionalNotesCtrl.text = s.additionalNotes;
    _category = s.caseSheetCategory;
    _extCtrl.populateFromSheet(s);
  }

  @override
  Widget build(BuildContext context) {
    final completedCount =
        _sheet.completedSectionsCount(isFemale: _isPatientFemale);
    final totalCount = _sheet.totalSectionsCount(isFemale: _isPatientFemale);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Homeopathic Case Taking',
              style: TextStyle(
                fontFamily: AppColors.headingFontFamily,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              '${widget.patient.fullName} • ${widget.patient.age}y / ${widget.patient.gender}',
              style: AppColors.bodySmall,
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                foregroundColor: const Color(0xFF2E7D32),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Color(0xFF81C784), width: 0.8),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_rounded, size: 16),
              label: const Text(
                'Voice Scribe',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: _launchVoiceScribe,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: totalCount > 0 ? completedCount / totalCount : 0.0,
                      backgroundColor: AppColors.divider,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.positiveGreen,
                      ),
                      minHeight: 6,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$completedCount of $totalCount sections',
                  style: const TextStyle(
                    fontFamily: AppColors.bodyFontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          // Category Selector: General, Children, Female & Endocrine, Acute
          HomeopathyCategorySelector(
            selectedCategory: _category,
            patientAge: widget.patient.age,
            isFemale: _isPatientFemale,
            onCategoryChanged: (cat) {
              setState(() {
                _category = cat;
                if (cat == HomeopathyCaseSheetCategory.acute &&
                    _sheet.overview.caseType != HomeopathyCaseType.acute) {
                  _sheet = _sheet.copyWith(
                    overview: _sheet.overview.copyWith(
                      caseType: HomeopathyCaseType.acute,
                    ),
                  );
                }
              });
            },
          ),

          // Section A: Case Overview
          _buildAccordionCard(
            title: 'A. Case Overview',
            subtitle: _sheet.overview.caseType.label,
            isComplete: _sheet.overview.isCompleted,
            icon: Icons.assignment_outlined,
            children: [
              // Acute vs Chronic toggle
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Chronic Case')),
                      selected: _sheet.overview.caseType == HomeopathyCaseType.chronic,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _sheet = _sheet.copyWith(
                              overview: _sheet.overview.copyWith(
                                caseType: HomeopathyCaseType.chronic,
                              ),
                            );
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('Acute Case')),
                      selected: _sheet.overview.caseType == HomeopathyCaseType.acute,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _sheet = _sheet.copyWith(
                              overview: _sheet.overview.copyWith(
                                caseType: HomeopathyCaseType.acute,
                              ),
                            );
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _chiefProblemCtrl,
                label: 'Chief Problem / Presenting Issue *',
                hint: 'e.g. Recurrent migraine headaches, skin eczema',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _consultationReasonCtrl,
                label: 'Reason for Consultation / Expectations',
                hint: 'Why patient is seeking homeopathic constitutional treatment',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _perceivedCauseCtrl,
                label: 'Patient\'s Perceived Cause (Physical or Emotional)',
                hint: 'What caused the complaint according to the patient? (e.g. Grief, cold wind, injury, work stress)',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _priorHomeoExpCtrl,
                      label: 'Prior Homeopathy Use',
                      hint: 'Past remedies / reactions / suppressions',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _referralSourceCtrl,
                      label: 'How Known About Us',
                      hint: 'Referral, Google, Family, Social',
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Specialized Questionnaires (Children, Female & Endocrine, Acute)
          if (_category == HomeopathyCaseSheetCategory.children)
            _buildChildrenPediatricCard(),

          if (_category == HomeopathyCaseSheetCategory.femaleEndocrine)
            _buildFemaleEndocrineCard(),

          if (_category == HomeopathyCaseSheetCategory.acute)
            _buildAcuteCaseSheetCard(),

          // Section B: Chief Complaint
          if (_category == HomeopathyCaseSheetCategory.general ||
              _category == HomeopathyCaseSheetCategory.femaleEndocrine)
          _buildAccordionCard(
            title: 'B. Chief Complaint & Description',
            subtitle: 'Location, Sensation, Onset, Progression',
            isComplete: _sheet.chiefComplaint.isCompleted,
            icon: Icons.healing_outlined,
            children: [
              _buildTextField(
                controller: _complaintCtrl,
                label: 'Detailed Complaint',
                hint: 'Describe patient\'s chief complaint in their own words',
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _locationCtrl,
                      label: 'Location / Side',
                      hint: 'e.g. Right hypochondrium, forehead',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _sensationCtrl,
                      label: 'Sensation',
                      hint: 'e.g. Burning, stitching, throbbing',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _onsetCtrl,
                      label: 'Onset',
                      hint: 'Sudden or gradual',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _durationCtrl,
                      label: 'Duration',
                      hint: 'e.g. 6 months, 3 weeks',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _frequencyCtrl,
                      label: 'Frequency',
                      hint: 'e.g. Daily, periodic, seasonal',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _progressionCtrl,
                      label: 'Progression',
                      hint: 'Improving, worsening, constant',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _triggeringCausesCtrl,
                label: 'Triggering Causes / Aetiology',
                hint: 'After grief, exposure to cold wind, wet weather, anger, bad food',
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _associatedSymptomsCtrl,
                label: 'Associated Symptoms',
                hint: 'Accompanying complaints occurring with main problem',
              ),
            ],
          ),

          // Section C: Modalities (< Aggravations & > Ameliorations)
          if (_category == HomeopathyCaseSheetCategory.general)
          _buildAccordionCard(
            title: 'C. Modalities (< Aggravations & > Ameliorations)',
            subtitle: 'Time, Position, Weather, Temperature, Motion',
            isComplete: _sheet.modalities.isCompleted,
            icon: Icons.tune_rounded,
            children: [
              _buildTextField(
                controller: _aggravatingCtrl,
                label: '< Aggravating Factors (Worse from)',
                hint: 'e.g. Cold air, motion, night (3 AM), fatty foods, dampness',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _amelioratingCtrl,
                label: '> Ameliorating Factors (Better from)',
                hint: 'e.g. Warm applications, resting, open air, hard pressure, eating',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _timePatternsCtrl,
                      label: 'Time Modality',
                      hint: 'Morning, evening, midnight, periodically',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _positionCtrl,
                      label: 'Position Modality',
                      hint: 'Lying, sitting, bending double',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _motionCtrl,
                      label: 'Motion / Rest',
                      hint: 'Continued motion, initial motion, rest',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _temperatureWeatherCtrl,
                      label: 'Weather & Temperature',
                      hint: 'Rainy, stormy, heat of sun, draft of air',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _foodDrinkModalitiesCtrl,
                label: 'Food & Drink Modalities',
                hint: 'Aggravation from milk, tea, coffee, sweets, spicy food',
              ),
            ],
          ),

          // Section D: General Symptoms & Thermal State
          if (_category == HomeopathyCaseSheetCategory.general)
          _buildAccordionCard(
            title: 'D. General Symptoms & Thermal State',
            subtitle: 'Thermal reaction, Cravings, Aversions, Thirst, Sleep',
            isComplete: _sheet.generalSymptoms.isCompleted,
            icon: Icons.thermostat_rounded,
            children: [
              const Text(
                'Thermal State (Crucial Keynote) *',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('❄️ Chilly'),
                    selected: _sheet.generalSymptoms.thermalState ==
                        HomeopathyThermalState.chilly,
                    onSelected: (val) {
                      setState(() {
                        _sheet = _sheet.copyWith(
                          generalSymptoms: _sheet.generalSymptoms.copyWith(
                            thermalState: val
                                ? HomeopathyThermalState.chilly
                                : HomeopathyThermalState.unspecified,
                          ),
                        );
                      });
                    },
                  ),
                  ChoiceChip(
                    label: const Text('🔥 Hot'),
                    selected: _sheet.generalSymptoms.thermalState ==
                        HomeopathyThermalState.hot,
                    onSelected: (val) {
                      setState(() {
                        _sheet = _sheet.copyWith(
                          generalSymptoms: _sheet.generalSymptoms.copyWith(
                            thermalState: val
                                ? HomeopathyThermalState.hot
                                : HomeopathyThermalState.unspecified,
                          ),
                        );
                      });
                    },
                  ),
                  ChoiceChip(
                    label: const Text('⚖️ Ambithermal'),
                    selected: _sheet.generalSymptoms.thermalState ==
                        HomeopathyThermalState.ambithermal,
                    onSelected: (val) {
                      setState(() {
                        _sheet = _sheet.copyWith(
                          generalSymptoms: _sheet.generalSymptoms.copyWith(
                            thermalState: val
                                ? HomeopathyThermalState.ambithermal
                                : HomeopathyThermalState.unspecified,
                          ),
                        );
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Thirst Quick-chips
              const Text(
                'Thirst Pattern',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  'Thirsty - large quantities',
                  'Thirsty - small sips frequently',
                  'Thirstless even with fever',
                  'Craves cold ice water',
                  'Craves warm drinks',
                ].map((thirstPreset) {
                  final isSelected = _thirstCtrl.text == thirstPreset;
                  return FilterChip(
                    label: Text(thirstPreset, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (sel) {
                      setState(() {
                        _thirstCtrl.text = sel ? thirstPreset : '';
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _thirstCtrl,
                label: 'Thirst Details',
                hint: 'Quantity, frequency, temperature preference',
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _thirstStyleCtrl,
                label: 'Manner of Drinking Water',
                hint: 'e.g. Sips frequently (Ars), large gulps at long intervals (Bry), gulps rapidly',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _extCtrl.thirstTimeCtrl,
                      label: 'Thirst Time / Modal Hour',
                      hint: 'Night, morning, during chill/heat',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _extCtrl.tasteChangesCtrl,
                      label: 'Taste in Mouth / Changes',
                      hint: 'Bitter, metallic, salty, sour, sweet, lost',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Food Cravings & Aversions
              const Text(
                'Common Food Desires / Cravings',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  'Sweets / Sugar',
                  'Salty items',
                  'Sour / Pickles',
                  'Spicy / Pungent',
                  'Fried / Fatty food',
                  'Ice / Cold food',
                  'Eggs',
                  'Warm milk',
                ].map((item) {
                  final list = _sheet.generalSymptoms.cravingsDesires;
                  final isPresent = list.contains(item);
                  return FilterChip(
                    label: Text(item, style: const TextStyle(fontSize: 12)),
                    selected: isPresent,
                    onSelected: (sel) {
                      final updated = List<String>.from(list);
                      if (sel) {
                        updated.add(item);
                      } else {
                        updated.remove(item);
                      }
                      setState(() {
                        _sheet = _sheet.copyWith(
                          generalSymptoms: _sheet.generalSymptoms.copyWith(
                            cravingsDesires: updated,
                          ),
                        );
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _appetiteCtrl,
                      label: 'Appetite',
                      hint: 'Ravenous, decreased, easily satisfied',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _perspirationCtrl,
                      label: 'Perspiration / Sweat',
                      hint: 'Profuse, offensive, stains yellow, head only',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _extCtrl.hungerTimeCtrl,
                      label: 'Hunger Time & Fasting Effect',
                      hint: 'Aggravation from fasting, 11 AM hunger (Sulph)',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _extCtrl.eatingSpeedCtrl,
                      label: 'Eating Speed',
                      hint: 'Eats hastily/in hurry, slow eater',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _extCtrl.hungerReactionCtrl,
                label: 'Reaction if Meal Delayed',
                hint: 'Headache, trembling, irritability, faintness (Lyc, Sulph)',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _perspLocationCtrl,
                      label: 'Perspiration Location',
                      hint: 'Head/occiput, palms, soles, chest, axillae',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _perspOdourCtrl,
                      label: 'Perspiration Odour / Staining',
                      hint: 'Sour, offensive, sweet, stains yellow, oily',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _stoolsCtrl,
                      label: 'Stool & Bowels',
                      hint: 'Constipation, ineffectual urging, diarrhea',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _urineCtrl,
                      label: 'Urine',
                      hint: 'Frequency, burning, strong odor',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _skinCtrl,
                      label: 'Skin Conditions',
                      hint: 'Dry, unhealthy, eruptions, itching',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _energyCtrl,
                      label: 'Energy & Weakness',
                      hint: 'Fatigue time, prostration',
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Section E: Physical Symptoms
          if (_category == HomeopathyCaseSheetCategory.general)
          _buildAccordionCard(
            title: 'E. Physical Symptoms by Systems',
            subtitle: 'Joints, Respiratory, ENT, Headaches, Fever, Pain',
            isComplete: _sheet.physicalSymptoms.isCompleted,
            icon: Icons.accessibility_new_rounded,
            children: [
              _buildTextField(
                controller: _rheumatologyCtrl,
                label: 'Musculoskeletal & Joints',
                hint: 'Stiffness on waking, gouty swellings, cracking joints',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _faceEntCtrl,
                      label: 'Face & ENT',
                      hint: 'Sinus congestion, epistaxis, polyps, tinnitus',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _headVertigoCtrl,
                      label: 'Head & Vertigo Symptoms',
                      hint: 'Headache location, sidedness, dizziness',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _respiratoryCtrl,
                label: 'Respiratory (Chest, Dyspnea, Asthma)',
                hint: 'Breathing difficulty, chest oppression, asthmatic wheeze',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _coughTypeCtrl,
                      label: 'Cough Type',
                      hint: 'Dry, loose, paroxysmal, barking, rattling',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _sputumDetailsCtrl,
                      label: 'Sputum / Expectoration',
                      hint: 'Yellow/green/rusty, thick, frothy, blood-streaked',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _coughTasteCtrl,
                label: 'Taste in Mouth during Cough / Illness',
                hint: 'Metallic, bitter, salty, sour, sweet, putrid',
              ),
              const SizedBox(height: 14),
              const Text(
                'Acute Fever Stages',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _feverChillCtrl,
                      label: 'Chill Stage',
                      hint: 'Onset direction, shivering, thirst',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _feverHeatCtrl,
                      label: 'Heat / Flush Stage',
                      hint: 'Burning dry heat, thirst during heat',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _feverSweatCtrl,
                      label: 'Sweat Stage',
                      hint: 'Profuse/scanty, relief after sweat',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _feverPeriodicityCtrl,
                      label: 'Fever Periodicity / Spike Time',
                      hint: 'Alternate days, 3 PM-8 PM, night rise',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _digestiveStoolCtrl,
                label: 'Gastrointestinal & Bowels (Diarrhea / Dysentery / Tenesmus)',
                hint: 'Stool consistency, color, ineffectual urging, relief or aggravation after stool',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _cnsCtrl,
                label: 'Central Nervous System',
                hint: 'Trembling, numbness, twitching, sensory changes',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _painCharCtrl,
                      label: 'Pain Characteristics',
                      hint: 'Stitching, burning, throbbing, shooting',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _painLocCtrl,
                      label: 'Pain Location',
                      hint: 'Exact site & radiation',
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Section F: Female / Reproductive History (Conditional / Adaptive)
          if (_isPatientFemale &&
              (_category == HomeopathyCaseSheetCategory.general ||
                  _category == HomeopathyCaseSheetCategory.femaleEndocrine))
            _buildAccordionCard(
              title: 'F. Female / Reproductive History',
              subtitle: 'Menstrual cycle, Menopause, Leucorrhoea',
              isComplete: _sheet.femaleReproductive.isCompleted,
              icon: Icons.pregnant_woman_rounded,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _mensesCycleCtrl,
                        label: 'Menstrual Cycle',
                        hint: 'Regular, early, delayed (e.g. 28 days)',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTextField(
                        controller: _mensesDurationCtrl,
                        label: 'Duration',
                        hint: 'e.g. 3-5 days',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _flowCharCtrl,
                        label: 'Flow Character',
                        hint: 'Profuse, scanty, dark, clotted, acrid',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTextField(
                        controller: _leucorrhoeaCtrl,
                        label: 'Leucorrhoea',
                        hint: 'Color, consistency, itching, stains',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _suppressionCtrl,
                  label: 'Menstrual Suppression & Consequences',
                  hint: 'Suppression from getting feet wet, grief, anger; resulting ailments',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _menopauseCtrl,
                        label: 'Menopause Details',
                        hint: 'Hot flushes, palpitations',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTextField(
                        controller: _obstetricCtrl,
                        label: 'Obstetric History',
                        hint: 'Gravida, Para, abortions',
                      ),
                    ),
                  ],
                ),
              ],
            ),

          // Section G: Mental & Emotional State
          if (_category == HomeopathyCaseSheetCategory.general)
          _buildAccordionCard(
            title: 'G. Mental & Emotional State',
            subtitle: 'Disposition, Fears, Anxiety, Consolation, Aetiology',
            isComplete: _sheet.mentalEmotional.isCompleted,
            icon: Icons.psychology_rounded,
            children: [
              _buildTextField(
                controller: _dispositionCtrl,
                label: 'General Disposition',
                hint: 'Mild, irritable, hurried, weeping, fastidious, reserved, stubborn',
              ),
              const SizedBox(height: 14),
              // Common Fears Quick-chips
              const Text(
                'Fears & Phobias',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  'Fear of Dark',
                  'Fear of Being Alone',
                  'Fear of Death',
                  'Fear of Disease / Illness',
                  'Fear of Heights',
                  'Fear of Dogs / Animals',
                  'Fear of Thunderstorm',
                  'Fear of Crowd',
                  'Fear of Narrow spaces',
                  'Fear of Failure',
                ].map((fear) {
                  final list = _sheet.mentalEmotional.fears;
                  final isPresent = list.contains(fear);
                  return FilterChip(
                    label: Text(fear, style: const TextStyle(fontSize: 12)),
                    selected: isPresent,
                    onSelected: (sel) {
                      final updated = List<String>.from(list);
                      if (sel) {
                        updated.add(fear);
                      } else {
                        updated.remove(fear);
                      }
                      setState(() {
                        _sheet = _sheet.copyWith(
                          mentalEmotional: _sheet.mentalEmotional.copyWith(
                            fears: updated,
                          ),
                        );
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              const Text(
                'Reaction to Disease & Illness',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  'Fears death / Fatalistic',
                  'Despair of recovery',
                  'Indifferent / Apathetic to illness',
                  'Hypochondriac / High anxiety',
                  'Demanding, complaining & irritable',
                  'Calm & resigned',
                ].map((item) {
                  final isSelected = _reactionToDiseaseCtrl.text == item;
                  return FilterChip(
                    label: Text(item, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (sel) {
                      setState(() {
                        _reactionToDiseaseCtrl.text = sel ? item : '';
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _reactionToDiseaseCtrl,
                label: 'Reaction to Disease Details',
                hint: 'Patient\'s attitude towards illness and suffering',
              ),
              const SizedBox(height: 14),
              const Text(
                'Demeanor / Sensorium during Illness',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  'Dullness, drowsiness & apathy',
                  'Restless tossing in bed',
                  'Quiet stupor / Desires silence',
                  'Hurried, agitated & impatient',
                ].map((item) {
                  final isSelected = _dullnessRestlessCtrl.text == item;
                  return FilterChip(
                    label: Text(item, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (sel) {
                      setState(() {
                        _dullnessRestlessCtrl.text = sel ? item : '';
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _dullnessRestlessCtrl,
                label: 'Demeanor Details',
                hint: 'Restlessness vs dullness behavior in illness',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _facialExpressionCtrl,
                      label: 'Facial Expression & Demeanor',
                      hint: 'Anxious, pale, flushed, sunken, glassy',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _mentalShiftCtrl,
                      label: 'Mental Shift Since Illness',
                      hint: 'How mood changed since disease began',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Consolation Reaction Quick-chips
              const Text(
                'Reaction to Consolation',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  'Aggravates from consolation (Angered)',
                  'Ameliorates from consolation (Soothed)',
                  'Indifferent to consolation',
                ].map((cons) {
                  final isSelected = _consolationCtrl.text == cons;
                  return FilterChip(
                    label: Text(cons, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (sel) {
                      setState(() {
                        _consolationCtrl.text = sel ? cons : '';
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _anxietyCtrl,
                      label: 'Anxiety & Worries',
                      hint: 'Health, family, financial',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _companySolitudeCtrl,
                      label: 'Company vs Alone',
                      hint: 'Craves company or desires solitude',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _emotionalTriggersCtrl,
                label: 'Emotional Aetiology (Causes)',
                hint: 'Ailments from grief, mortification, suppressed anger, fright, shock',
              ),
              const SizedBox(height: 14),
              const Text(
                'Family & Interpersonal Dynamics (Relationships & Stressors)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _familyDynamicsCtrl,
                      label: 'Family Atmosphere',
                      hint: 'Domestic environment, harmony',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _spouseRelCtrl,
                      label: 'Spouse / Marriage',
                      hint: 'Relationship with spouse, conflicts',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _childrenRelCtrl,
                      label: 'Children',
                      hint: 'Parenting stress, relations with kids',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _inlawsRelCtrl,
                      label: 'In-Laws',
                      hint: 'Domestic friction with in-laws',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _colleaguesCtrl,
                      label: 'Colleagues & Workplace',
                      hint: 'Job stress, interpersonal frictions',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _majorTensionsCtrl,
                      label: 'Major Life Tensions',
                      hint: 'Financial strain, legal, chronic tensions',
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Detailed Mind & Personality Questionnaire (Q1–Q18)
          if (_category == HomeopathyCaseSheetCategory.general)
            _buildExpandedMindPersonalityCard(),

          // Section H: Dreams & Sleep
          if (_category == HomeopathyCaseSheetCategory.general)
          _buildAccordionCard(
            title: 'H. Dreams & Sleep Profile',
            subtitle: 'Sleep quality, disturbances, recurring dreams',
            isComplete: _sheet.dreamsSleep.isCompleted,
            icon: Icons.bedtime_outlined,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _sleepQualityCtrl,
                      label: 'Sleep Quality',
                      hint: 'Refreshing, unrefreshing, restless',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _sleepDisturbancesCtrl,
                      label: 'Sleep Disturbances',
                      hint: 'Waking at 3 AM, insomnia, night terrors',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Common / Recurring Dreams',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  'Falling from heights',
                  'Flying',
                  'Water / Drowning',
                  'Dead relatives',
                  'Animals / Snakes',
                  'Robbers / Thieves',
                  'Being chased / Danger',
                  'Daily business',
                  'Examinations / Unprepared',
                ].map((dream) {
                  final list = _sheet.dreamsSleep.recurringDreams;
                  final isPresent = list.contains(dream);
                  return FilterChip(
                    label: Text(dream, style: const TextStyle(fontSize: 12)),
                    selected: isPresent,
                    onSelected: (sel) {
                      final updated = List<String>.from(list);
                      if (sel) {
                        updated.add(dream);
                      } else {
                        updated.remove(dream);
                      }
                      setState(() {
                        _sheet = _sheet.copyWith(
                          dreamsSleep: _sheet.dreamsSleep.copyWith(
                            recurringDreams: updated,
                          ),
                        );
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _dreamCharCtrl,
                label: 'Dream Characteristics & Feelings upon waking',
                hint: 'Anxious, vivid, frightful, pleasant',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _extCtrl.sleepPostureCtrl,
                      label: 'Sleep Posture',
                      hint: 'On back, abdomen, right side, left side',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _extCtrl.sleepRestrictionsCtrl,
                      label: 'Position Restrictions',
                      hint: 'Cannot lie on left side (heart), flat',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _extCtrl.sleepBehaviorsCtrl,
                label: 'Sleep Behaviors',
                hint: 'Grinding teeth, talking, laughing, snoring, twitching, starts in sleep',
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _extCtrl.childhoodDreamsCtrl,
                label: 'Childhood Dreams (if recurring)',
                hint: 'Monsters, falling, ghosts, animals, exams',
              ),
            ],
          ),

          // Childhood History (General Case Sheet Q25)
          if (_category == HomeopathyCaseSheetCategory.general)
            _buildChildhoodHistoryCard(),

          // Section I: Sexual History (Discreet & Collapsible with privacy lock)
          if (_category == HomeopathyCaseSheetCategory.general)
          _buildAccordionCard(
            title: 'I. Sexual History (Privacy Protected)',
            subtitle: 'Desire level, complaints, sensitive concerns',
            isComplete: _sheet.sexualHistory.isCompleted,
            icon: Icons.lock_outline_rounded,
            children: [
              if (!_sexualHistoryUnlocked)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('Unlock & View Sensitive Section'),
                      onPressed: () {
                        setState(() => _sexualHistoryUnlocked = true);
                      },
                    ),
                  ),
                )
              else ...[
                _buildTextField(
                  controller: _desireLevelCtrl,
                  label: 'Sexual Desires',
                  hint: 'Normal, increased, diminished, absent, aversions',
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _sexualConcernsCtrl,
                  label: 'Complaints / Physical Concerns',
                  hint: 'Specific clinical symptoms or dysfunction',
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _sexualNotesCtrl,
                  label: 'Confidential Clinical Notes',
                  hint: 'Additional notes for practitioner reference',
                  maxLines: 2,
                ),
              ],
            ],
          ),

          // Section J: Medical / Health History
          if (_category == HomeopathyCaseSheetCategory.general)
          _buildAccordionCard(
            title: 'J. Past Medical & Family History',
            subtitle: 'Illnesses, Surgeries, Medications, Allergies, Family',
            isComplete: _sheet.medicalHistory.isCompleted,
            icon: Icons.history_edu_rounded,
            children: [
              _buildTextField(
                controller: _pastIllnessesCtrl,
                label: 'Past Illnesses',
                hint: 'Typhoid, jaundice, recurrent pneumonia, measles, malaria',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _surgeriesCtrl,
                      label: 'Surgical & Injury History',
                      hint: 'Appendectomy, fractures, head injury',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _medicationsCtrl,
                      label: 'Past / Current Allopathic Meds',
                      hint: 'Steroids, antibiotics, painkillers',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _allergiesCtrl,
                      label: 'Allergies & Sensitivities',
                      hint: 'Dust, pollen, penicillin, sulfur',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _familyHistoryCtrl,
                      label: 'Family Medical History',
                      hint: 'T.B., Cancer, Diabetes, Asthma, Autoimmune',
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Section K: Physical Examination
          _buildAccordionCard(
            title: 'K. Physical Examination',
            subtitle: 'Tongue, Constitution, Pulse, BP, Tender spots',
            isComplete: _sheet.physicalExamination.isCompleted,
            icon: Icons.medical_services_outlined,
            children: [
              _buildTextField(
                controller: _constitutionCtrl,
                label: 'Physical Constitution & Build',
                hint: 'Lean, obese, plethoric, pale, flushed, posture',
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _tongueExamCtrl,
                label: 'Tongue Examination (Homeopathic Keynote)',
                hint: 'White coated, yellow at base, mapped, red edges, teeth indentations',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _pulseBpCtrl,
                      label: 'Pulse & BP',
                      hint: 'BP 120/80, Pulse 74/min',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildTextField(
                      controller: _sensitiveAreasCtrl,
                      label: 'Tender / Sensitive Areas',
                      hint: 'Epigastric tenderness, spinal spots',
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Section L: Investigations & Diagnostics
          if (_category != HomeopathyCaseSheetCategory.acute)
          _buildAccordionCard(
            title: 'L. Investigations & Lab Reports',
            subtitle: 'Blood tests, imaging, scan findings',
            isComplete: _sheet.investigations.isCompleted,
            icon: Icons.science_outlined,
            children: [
              _buildTextField(
                controller: _labReportsCtrl,
                label: 'Laboratory Test Results',
                hint: 'CBC, ESR, Blood Sugar, Thyroid panel, Urine R/M',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _imagingNotesCtrl,
                label: 'Imaging & Diagnostics',
                hint: 'X-Ray, Ultrasound, MRI reports summary',
                maxLines: 2,
              ),
            ],
          ),

          // Section M: Peculiar Symptoms (SRP Keynotes)
          if (_category == HomeopathyCaseSheetCategory.general)
          _buildAccordionCard(
            title: 'M. Strange, Rare & Peculiar (SRP) Symptoms',
            subtitle: 'Unusual symptom patterns, Keynotes, Idiosyncrasies',
            isComplete: _sheet.peculiarSymptoms.isCompleted,
            icon: Icons.star_border_rounded,
            children: [
              _buildTextField(
                controller: _peculiarSrpCtrl,
                label: 'SRP Symptoms ("As if..." sensations & keynotes)',
                hint: 'e.g. Sensation of a lump of ice in stomach, sleeps with head low',
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _keynoteObsCtrl,
                label: 'Keynote Clinical Observations',
                hint: 'Distinctive characteristic indications pointing to specific remedy',
                maxLines: 2,
              ),
            ],
          ),

          // Section N: Prescription, Repertorization & Advice
          _buildAccordionCard(
            title: 'N. Repertorization & Prescribed Remedy',
            subtitle: 'Miasm, Simillimum remedy, Potency, Regimen',
            isComplete: _sheet.prescriptionNotes.isCompleted,
            icon: Icons.medication_outlined,
            initiallyExpanded: true,
            children: [
              // Miasmatic Tendency Chips
              const Text(
                'Miasmatic Predominance',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  'Psora',
                  'Sycosis',
                  'Syphilis',
                  'Tubercular',
                  'Mixed Miasm',
                ].map((miasm) {
                  final isSelected = _miasmCtrl.text == miasm;
                  return FilterChip(
                    label: Text(miasm, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (sel) {
                      setState(() {
                        _miasmCtrl.text = sel ? miasm : '';
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      controller: _remedyCtrl,
                      label: 'Prescribed Remedy (Simillimum) *',
                      hint: 'e.g. Lycopodium, Natrum Mur, Pulsatilla',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 1,
                    child: _buildTextField(
                      controller: _potencyCtrl,
                      label: 'Potency',
                      hint: '30C, 200C, 1M, 0/1 LM',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _totalityRubricsCtrl,
                label: 'Totality of Symptoms (Core Synthesis)',
                hint: 'Synthesis of key mental, general, and peculiar SRP symptoms',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _differentialRemediesCtrl,
                label: 'Differential Remedies Considered',
                hint: 'Close running remedies and reasons for choosing simillimum',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _repetitionCtrl,
                label: 'Dosage & Repetition Scale',
                hint: 'e.g. 4 pills once daily at night, or single dose weekly',
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _repertoryNotesCtrl,
                label: 'Repertorization Rubrics & Synthesis',
                hint: 'Key rubrics used in repertorization chart',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _adviceDietCtrl,
                label: 'Dietary & Lifestyle Advice',
                hint: 'Avoid raw onions, strong coffee, camphor ointments',
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _additionalNotesCtrl,
                label: 'General Clinical Notes',
                hint: 'Follow-up timeline and observation targets',
                maxLines: 2,
              ),
            ],
          ),

          // Section O: Follow-Up & Second Prescription
          _buildAccordionCard(
            title: 'O. Follow-Up & Second Prescription',
            subtitle: 'Clinical response, Direction of cure, Next prescription plan',
            isComplete: _sheet.followUp.isCompleted,
            icon: Icons.update_rounded,
            children: [
              const Text(
                'Clinical Response Rating',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  'Marked Improvement (Amelioration)',
                  'Moderate Improvement',
                  'Status Quo (No Change)',
                  'Homeopathic Aggravation',
                  'Disease Aggravation',
                  'New Symptoms Appeared',
                ].map((resp) {
                  final isSelected = _followUpResponseCtrl.text == resp;
                  return FilterChip(
                    label: Text(resp, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (sel) {
                      setState(() {
                        _followUpResponseCtrl.text = sel ? resp : '';
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              const Text(
                'Direction of Cure (Hering\'s Law)',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  'Inside-outward (Center to periphery)',
                  'Above-downward (Head to limbs)',
                  'Reverse order of symptoms',
                  'Disorderly / Outward to inward (Suppression warning)',
                ].map((hering) {
                  final isSelected = _heringsLawCtrl.text == hering;
                  return FilterChip(
                    label: Text(hering, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (sel) {
                      setState(() {
                        _heringsLawCtrl.text = sel ? hering : '';
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              const Text(
                'Next Prescription Action Plan',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  'Continue Same (Sac Lac / Placebo)',
                  'Increase Potency (Progress ceased)',
                  'Repeat Dose (Action active)',
                  'Change Remedy (New totality)',
                  'Wait & Watch (Remedy unfolding)',
                ].map((action) {
                  final isSelected = _nextPrescriptionPlanCtrl.text == action;
                  return FilterChip(
                    label: Text(action, style: const TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (sel) {
                      setState(() {
                        _nextPrescriptionPlanCtrl.text = sel ? action : '';
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              _buildTextField(
                controller: _clinicalChangesCtrl,
                label: 'Clinical Changes Observed',
                hint: 'Changes in chief complaint, energy, well-being, mood',
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _followUpNotesCtrl,
                label: 'Follow-Up Notes & Instructions',
                hint: 'Specific observation goals, date to review, SOS instructions',
                maxLines: 2,
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              offset: const Offset(0, -3),
              blurRadius: 10,
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.divider),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSaving
                      ? null
                      : () => _saveCase(markComplete: false),
                  child: const Text(
                    'Save Draft',
                    style: TextStyle(
                      fontFamily: AppColors.bodyFontFamily,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.positiveGreen,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isSaving
                      ? null
                      : () => _saveCase(markComplete: true),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Save & Complete',
                          style: TextStyle(
                            fontFamily: AppColors.bodyFontFamily,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccordionCard({
    required String title,
    required String subtitle,
    required bool isComplete,
    required IconData icon,
    required List<Widget> children,
    bool initiallyExpanded = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isComplete
              ? AppColors.positiveGreen.withValues(alpha: 0.35)
              : const Color(0xFFE2E8F0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            offset: const Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isComplete
                  ? AppColors.positiveGreen.withValues(alpha: 0.12)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isComplete
                  ? AppColors.positiveGreen
                  : AppColors.slateBlue,
            ),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontFamily: AppColors.headingFontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              fontFamily: AppColors.bodyFontFamily,
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isComplete)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.positiveGreen,
                    size: 18,
                  ),
                ),
              const Icon(
                Icons.expand_more_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: children,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    bool enableVoice = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: AppColors.bodyFontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (enableVoice)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () async {
                  final text = await HomeopathyVoiceDictationSheet.show(
                    context,
                    fieldName: label,
                    initialText: controller.text,
                  );
                  if (text != null && text.trim().isNotEmpty) {
                    setState(() {
                      if (controller.text.trim().isEmpty) {
                        controller.text = text.trim();
                      } else {
                        controller.text =
                            '${controller.text.trim()}\n${text.trim()}';
                      }
                    });
                  }
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.mic_rounded,
                        size: 14,
                        color: Color(0xFF2E7D32),
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Speak',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2E7D32),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 12,
              color: Color(0xFF94A3B8),
            ),
            suffixIcon: enableVoice
                ? IconButton(
                    icon: const Icon(Icons.mic_none_rounded, size: 18),
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.8),
                    tooltip: 'Speak to fill $label',
                    onPressed: () async {
                      final text = await HomeopathyVoiceDictationSheet.show(
                        context,
                        fieldName: label,
                        initialText: controller.text,
                      );
                      if (text != null && text.trim().isNotEmpty) {
                        setState(() {
                          if (controller.text.trim().isEmpty) {
                            controller.text = text.trim();
                          } else {
                            controller.text =
                                '${controller.text.trim()}\n${text.trim()}';
                          }
                        });
                      }
                    },
                  )
                : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  const BorderSide(color: Color(0xFF2E7D32), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChildrenPediatricCard() {
    return ChildrenPediatricFormCard(
      coldHeatCtrl: _extCtrl.childColdHeatCtrl,
      behaviorWhenUpsetCtrl: _extCtrl.childBehaviorUpsetCtrl,
      whatMakesHappyCtrl: _extCtrl.childWhatMakesHappyCtrl,
      schoolBehaviorCtrl: _extCtrl.childSchoolBehaviorCtrl,
      graspingScoreCtrl: _extCtrl.childGraspingScoreCtrl,
      childTypeCtrl: _extCtrl.childTypeCtrl,
      vaccinationCtrl: _extCtrl.childVaccinationCtrl,
      favoriteSportCtrl: _extCtrl.childFavoriteSportCtrl,
      attitudeParentsCtrl: _extCtrl.childAttitudeParentsCtrl,
      medicalHistoryCtrl: _extCtrl.childMedicalHistoryCtrl,
      maturityCtrl: _extCtrl.childMaturityCtrl,
      familyProblemsCtrl: _extCtrl.childFamilyProblemsCtrl,
      introvertExtrovertCtrl: _extCtrl.childIntrovertCtrl,
      independenceCtrl: _extCtrl.childIndependenceCtrl,
      waterIntakeCtrl: _extCtrl.childWaterIntakeCtrl,
      birthComplicationsCtrl: _extCtrl.childBirthComplicationsCtrl,
      motherPregnancyCtrl: _extCtrl.childMotherPregnancyCtrl,
      motherMedicalCtrl: _extCtrl.childMotherMedicalCtrl,
      familyHereditaryCtrl: _extCtrl.childFamilyHereditaryCtrl,
      walkingTeethingCtrl: _extCtrl.childWalkingTeethingCtrl,
      abnormalBehaviorsCtrl: _extCtrl.childAbnormalBehaviorsCtrl,
      childFearsCtrl: _extCtrl.childFearsSpecificCtrl,
      sleepingHabitsCtrl: _extCtrl.childSleepingHabitsCtrl,
      abnormalCravingsCtrl: _extCtrl.abnormalCravingsCtrl,
      wormsCtrl: _extCtrl.childWormsCtrl,
      headCtrl: _extCtrl.childHeadCtrl,
      coughCtrl: _extCtrl.childCoughAsthmaCtrl,
      stomachCtrl: _extCtrl.childStomachCtrl,
      stoolCtrl: _extCtrl.childStoolRectumCtrl,
      sexualAwarenessCtrl: _extCtrl.childSexualAwarenessCtrl,
      additionalInfoCtrl: _extCtrl.childAdditionalInfoCtrl,
      isComplete: _sheet.childrenCaseSheet.isCompleted,
    );
  }

  Widget _buildFemaleEndocrineCard() {
    return FemaleEndocrineFormCard(
      diagnosisCtrl: _extCtrl.endoDiagnosisCtrl,
      howStartedCtrl: _extCtrl.endoHowStartedCtrl,
      physioTriggerCtrl: _extCtrl.endoPhysioTriggerCtrl,
      emotionalTriggerCtrl: _extCtrl.endoEmotionalTriggerCtrl,
      manifestationLocCtrl: _extCtrl.endoManifestationLocCtrl,
      otherOrgansCtrl: _extCtrl.endoOtherOrgansCtrl,
      goitreCtrl: _extCtrl.endoGoitreCtrl,
      glandsCtrl: _extCtrl.endoGlandsCtrl,
      skinCtrl: _extCtrl.endoSkinCtrl,
      cardiacCtrl: _extCtrl.endoCardiacCtrl,
      stagesOfLifeCtrl: _extCtrl.endoStagesOfLifeCtrl,
      menstrualCtrl: _extCtrl.endoMenstrualCtrl,
      weaknessCtrl: _extCtrl.endoWeaknessCtrl,
      relationshipsCtrl: _extCtrl.endoRelationshipsCtrl,
      isComplete: _sheet.femaleEndocrine.isCompleted,
    );
  }

  Widget _buildAcuteCaseSheetCard() {
    return AcuteCaseSheetCard(
      complaintCtrl: _extCtrl.acuteComplaintCtrl,
      causeCtrl: _extCtrl.acuteCauseCtrl,
      worseCtrl: _extCtrl.acuteWorseCtrl,
      betterCtrl: _extCtrl.acuteBetterCtrl,
      mentalConditionCtrl: _extCtrl.acuteMentalConditionCtrl,
      waterReqCtrl: _extCtrl.acuteWaterReqCtrl,
      sweatCtrl: _extCtrl.acuteSweatCtrl,
      postureCtrl: _extCtrl.acutePostureCtrl,
      feverCtrl: _extCtrl.acuteFeverCtrl,
      coughCtrl: _extCtrl.acuteCoughCtrl,
      looseDryCoughCtrl: _extCtrl.acuteLooseDryCoughCtrl,
      diarrheaCtrl: _extCtrl.acuteDiarrheaCtrl,
      painCtrl: _extCtrl.acutePainCtrl,
      uncommonSymptomsCtrl: _extCtrl.acuteUncommonSymptomsCtrl,
      additionalInfoCtrl: _extCtrl.acuteAdditionalInfoCtrl,
      isComplete: _sheet.acuteSheet.isCompleted,
    );
  }

  Widget _buildExpandedMindPersonalityCard() {
    return ExpandedMindPersonalityCard(
      upsetWorryCtrl: _extCtrl.upsetWorryCtrl,
      fearDetailsCtrl: _extCtrl.fearDetailsCtrl,
      introvertExtrovertCtrl: _extCtrl.introvertExtrovertCtrl,
      stressHistoryCtrl: _extCtrl.stressHistoryCtrl,
      stressCopingCtrl: _extCtrl.stressCopingCtrl,
      sensitivityDetailsCtrl: _extCtrl.sensitivityDetailsCtrl,
      fixedHabitsCtrl: _extCtrl.fixedHabitsCtrl,
      angerBodyCtrl: _extCtrl.angerBodyCtrl,
      disorderSensitivityCtrl: _extCtrl.disorderSensitivityCtrl,
      greatestGriefCtrl: _extCtrl.greatestGriefCtrl,
      greatestJoysCtrl: _extCtrl.greatestJoysCtrl,
      deeplyLikedCtrl: _extCtrl.deeplyLikedCtrl,
      deeplyDislikedCtrl: _extCtrl.deeplyDislikedCtrl,
      disagreeableMindCtrl: _extCtrl.disagreeableMindCtrl,
      lifeSituationCtrl: _extCtrl.lifeSituationCtrl,
      isComplete: _extCtrl.upsetWorryCtrl.text.trim().isNotEmpty ||
          _extCtrl.stressHistoryCtrl.text.trim().isNotEmpty ||
          _extCtrl.greatestGriefCtrl.text.trim().isNotEmpty,
    );
  }

  Widget _buildChildhoodHistoryCard() {
    return ChildhoodHistoryCard(
      natureCtrl: _extCtrl.childhoodNatureCtrl,
      habitsCtrl: _extCtrl.childhoodHabitsCtrl,
      fearsCtrl: _extCtrl.childhoodFearsCtrl,
      dreamsCtrl: _extCtrl.childhoodDreamsHistoryCtrl,
      relationshipsCtrl: _extCtrl.childhoodRelationshipsCtrl,
      sensitivitiesCtrl: _extCtrl.childhoodSensitivitiesCtrl,
      isComplete: _sheet.childhoodHistory.isCompleted,
    );
  }
}

