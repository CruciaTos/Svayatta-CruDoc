import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common/sqlite_api.dart' as sqflite_common;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;
import 'package:doctor_management_app/core/database/local_database.dart';
import 'package:doctor_management_app/core/database/windows_local_database.dart';
import 'package:doctor_management_app/core/models/doctor_specialty.dart';
import 'package:doctor_management_app/features/homeopathy/data/models/homeopathy_case_sheet.dart';
import 'package:doctor_management_app/features/homeopathy/services/homeopathy_voice_scribe_service.dart';

void main() {
  setUpAll(() {
    sqflite_ffi.sqfliteFfiInit();
  });

  group('DoctorSpecialty Speciality Resolution Tests', () {
    test('resolves homeopathy from diverse strings', () {
      expect(
        DoctorSpecialty.fromString('Homeopath').type,
        DoctorSpecialtyType.homeopathy,
      );
      expect(
        DoctorSpecialty.fromString('Homeopathy').type,
        DoctorSpecialtyType.homeopathy,
      );
      expect(
        DoctorSpecialty.fromString('classical homeopath').type,
        DoctorSpecialtyType.homeopathy,
      );
      expect(
        DoctorSpecialty.fromString('Homeo').type,
        DoctorSpecialtyType.homeopathy,
      );
    });

    test('resolves physiotherapy from diverse strings', () {
      expect(
        DoctorSpecialty.fromString('Physiotherapist').type,
        DoctorSpecialtyType.physiotherapy,
      );
      expect(
        DoctorSpecialty.fromString('Physiotherapy').type,
        DoctorSpecialtyType.physiotherapy,
      );
      expect(
        DoctorSpecialty.fromString('physio').type,
        DoctorSpecialtyType.physiotherapy,
      );
      expect(
        DoctorSpecialty.fromString('Physical Therapy').type,
        DoctorSpecialtyType.physiotherapy,
      );
      expect(
        DoctorSpecialty.fromString('Rehab Specialist').type,
        DoctorSpecialtyType.physiotherapy,
      );
      expect(
        DoctorSpecialty.fromString('BPT Ortho').type,
        DoctorSpecialtyType.physiotherapy,
      );
    });

    test('resolves general physician clearly and distinctly from physiotherapy', () {
      expect(
        DoctorSpecialty.fromString('General Physician').type,
        DoctorSpecialtyType.generalPhysician,
      );
      expect(
        DoctorSpecialty.fromString('Physician').type,
        DoctorSpecialtyType.generalPhysician,
      );
      expect(
        DoctorSpecialty.fromString('Internal Medicine').type,
        DoctorSpecialtyType.generalPhysician,
      );
      expect(
        DoctorSpecialty.fromString('Primary Care Physician').type,
        DoctorSpecialtyType.generalPhysician,
      );
      expect(
        DoctorSpecialty.fromString('MBBS Doctor').type,
        DoctorSpecialtyType.generalPhysician,
      );
      // Explicitly assert they are not equal
      expect(
        DoctorSpecialty.fromString('Physiotherapist').type !=
            DoctorSpecialty.fromString('General Physician').type,
        isTrue,
      );
    });

    test('falls back to General Physician when empty or unknown', () {
      expect(
        DoctorSpecialty.fromString(null).type,
        DoctorSpecialtyType.generalPhysician,
      );
      expect(
        DoctorSpecialty.fromString('').type,
        DoctorSpecialtyType.generalPhysician,
      );
      expect(
        DoctorSpecialty.fromString('Unknown Speciality').type,
        DoctorSpecialtyType.generalPhysician,
      );
    });
  });

  group('Homeopathy Thermal State Tests', () {
    test('parses chilly, hot, and ambithermal correctly', () {
      expect(HomeopathyThermalState.fromString('chilly'),
          HomeopathyThermalState.chilly);
      expect(
          HomeopathyThermalState.fromString('hot'), HomeopathyThermalState.hot);
      expect(HomeopathyThermalState.fromString('ambithermal'),
          HomeopathyThermalState.ambithermal);
      expect(HomeopathyThermalState.fromString('both'),
          HomeopathyThermalState.ambithermal);
      expect(HomeopathyThermalState.fromString('unknown'),
          HomeopathyThermalState.unspecified);
    });
  });

  group('HomeopathyCaseSheet Model Tests', () {
    test('creates empty case sheet with correct defaults', () {
      final sheet = HomeopathyCaseSheet.empty(
        id: 'case-123',
        patientId: 'patient-456',
        doctorId: 'doctor-789',
      );

      expect(sheet.id, 'case-123');
      expect(sheet.patientId, 'patient-456');
      expect(sheet.doctorId, 'doctor-789');
      expect(sheet.isCompleted, false);
      expect(sheet.overview.caseType, HomeopathyCaseType.chronic);
      expect(sheet.generalSymptoms.thermalState,
          HomeopathyThermalState.unspecified);
      expect(sheet.completedSectionsCount(), 0);
      expect(sheet.totalSectionsCount(isFemale: false), 15);
      expect(sheet.totalSectionsCount(isFemale: true), 16);
    });

    test('serializes to map and deserializes without data loss', () {
      final now = DateTime(2026, 9, 3, 12, 0);
      final sheet = HomeopathyCaseSheet(
        id: 'case-001',
        patientId: 'pat-001',
        doctorId: 'doc-001',
        isCompleted: true,
        overview: HomeopathyCaseOverview(
          caseType: HomeopathyCaseType.chronic,
          caseDate: now,
          chiefProblem: 'Chronic Migraine & Acid Reflux',
          priority: 'high',
          consultationReason: 'Constitutional Treatment',
          referralSource: 'Dr. Sharma Referral',
          priorHomeopathyExperience: 'Took Bryonia 30C last year with temporary relief',
          patientPerceivedCause: 'Severe work grief and mental exhaustion',
        ),
        chiefComplaint: const HomeopathyChiefComplaint(
          complaint: 'Throbbing right-sided headache with nausea',
          location: 'Right temporal region',
          sensationDescription: 'Hammering, throbbing pain',
          onset: 'Gradual',
          duration: '3 years',
          frequency: 'Twice a week',
          progression: 'Worsening with stress',
          triggeringCauses: 'Exposure to sun, skipped meals',
          associatedSymptoms: 'Photophobia, vomiting of sour fluid',
        ),
        modalities: const HomeopathyModalities(
          aggravatingFactors: 'Sun heat, 3 PM - 7 PM, mental exertion',
          amelioratingFactors: 'Dark quiet room, cold compress, sleep',
          timePatterns: 'Afternoon 3 PM',
          positionModalities: 'Lying on painful side worsens',
          motionModalities: 'Worse from motion, steps, jar',
          temperatureWeather: 'Worse hot sun, better open air',
          foodDrinkModalities: 'Aggravated by coffee and fatty food',
          otherTriggers: 'Fasting',
        ),
        generalSymptoms: const HomeopathyGeneralSymptoms(
          appetite: 'Good, but gets irritable when hungry',
          cravingsDesires: ['Sweets / Sugar', 'Warm food'],
          aversionsDislikes: ['Milk', 'Fatty meat'],
          thirst: 'Thirsty for large quantities of cold water',
          thirstStyle: 'Large gulps at long intervals',
          stools: 'Normal daily',
          urine: 'Clear',
          sleepPattern: 'Difficulty falling asleep before 1 AM',
          skinState: 'Dry skin',
          energyWeakness: 'Weakness in afternoon',
          thermalState: HomeopathyThermalState.chilly,
          perspiration: 'Scanty, mostly on neck and chest',
          perspirationLocation: 'Occiput and neck',
          perspirationOdour: 'Sour smelling',
        ),
        physicalSymptoms: const HomeopathyPhysicalSymptoms(
          rheumatologyJoints: 'Occasional knee stiffness',
          cnsNervous: 'Right sided migraine',
          faceEnt: 'Photophobia during attacks',
          respiratory: 'Clear',
          thermoregulationFever: 'No fever',
          feverChillStage: 'Chills starting in evening',
          feverHeatStage: 'Heat in head with cold feet',
          feverSweatStage: 'Sweat on face only',
          feverPeriodicity: 'Periodic every 7 days',
          coughType: 'Dry spasmodic cough',
          sputumDetails: 'Yellowish tenacious sputum',
          coughTasteInMouth: 'Bitter taste',
          digestiveStoolDetails: 'Constipation with ineffectual urging',
          headVertigoSymptoms: 'Vertigo when turning in bed',
          painCharacteristics: 'Throbbing, hammering',
          painLocation: 'Right temple',
          painIntensity: 8,
          painModalities: 'Worse light and noise',
        ),
        femaleReproductive: const HomeopathyFemaleHistory(
          mensesCycle: '28 days regular',
          mensesDuration: '4 days',
          flowCharacter: 'Moderate red',
          menopauseDetails: 'Not menopausal',
          menstrualSuppressionEffects: 'Headache worsens before menses',
          leucorrhoeaDetails: 'None',
          obstetricHistory: 'G1 P1',
        ),
        mentalEmotional: const HomeopathyMentalEmotional(
          disposition: 'Fastidious, intelligent, conscientious',
          fears: ['Fear of Failure', 'Fear of Disease / Illness'],
          anxietyTriggers: 'Work deadlines, health of family',
          companyVsSolitude: 'Prefers company in next room',
          reactionToConsolation: 'Ameliorates from consolation (Soothed)',
          emotionalAetiology: 'Prolonged mental overwork and stress',
          timeOfDayMood: 'Low in morning, brighter in evening',
          behavioralChanges: 'Becomes silent when in pain',
          familyDynamics: 'Supportive nuclear family',
          spouseRelationship: 'Harmonious, very supportive',
          childrenRelationship: 'Parenting stress with adolescent son',
          inlawsRelationship: 'Mild friction with mother-in-law',
          colleaguesWorkStress: 'High competition at corporate job',
          majorTensions: 'Upcoming property legal dispute',
          reactionToDisease: 'Fears death during severe acute migraines',
          dullnessVsRestlessness: 'Restless tossing during headache attacks',
          facialExpression: 'Tense, pale, anxious facies',
          mentalShiftSinceIllness: 'Normally gentle person becomes irritable',
        ),
        dreamsSleep: const HomeopathyDreamsSleep(
          sleepQuality: 'Unrefreshing',
          sleepDisturbances: 'Wakes at 4 AM thinking of work',
          recurringDreams: ['Falling from heights', 'Daily business'],
          dreamCharacteristics: 'Vivid and anxious',
        ),
        sexualHistory: const HomeopathySexualHistory(
          desireLevel: 'Normal',
          complaintsConcerns: 'None',
          notes: 'No complaints reported',
        ),
        medicalHistory: const HomeopathyMedicalHistory(
          pastIllnesses: 'Recurrent tonsillitis in childhood',
          surgicalHistory: 'None',
          pastMedications: 'Over-the-counter NSAIDs (Ibuprofen)',
          allergies: 'Allergic rhinitis to dust mites',
          vaccinationReactions: 'None',
          familyHistory: 'Mother had migraines, Father had hypertension',
        ),
        physicalExamination: const HomeopathyPhysicalExam(
          constitutionBuild: 'Lean, slight build, fair complexion',
          tongueExamination: 'Clean with red edges',
          nailsPulseBP: 'BP 118/76, Pulse 72/min regular',
          sensitiveAreas: 'Right supraorbital notch tender',
          clinicalObservations: 'Patient is articulate and observant',
        ),
        investigations: const HomeopathyInvestigations(
          labReports: 'CBC normal, Thyroid (TSH) 2.1 mIU/L within normal limits',
          imagingDiagnosticNotes: 'Brain MRI normal (reported 2025)',
        ),
        peculiarSymptoms: const HomeopathyPeculiarSymptoms(
          peculiarSRP: 'Headache begins with blurred vision and zigzag lights (scintillating scotoma)',
          keynoteObservations: 'Craves sweets, worse 4 PM, right-sided',
        ),
        prescriptionNotes: const HomeopathyPrescriptionNotes(
          repertorizationNotes: 'Lycopodium, Belladonna, Natrum Mur scored high',
          totalityOfSymptoms: 'Right-sided temporal headache + 4 PM aggravation + craves sweets + fanatical perfectionism',
          miasmaticTendency: 'Psora',
          prescribedRemedy: 'Lycopodium Clavatum',
          differentialRemedies: 'Belladonna (sudden onset, throbbing), Natrum Mur (sun headache, grief)',
          potency: '200C',
          repetitionScale: 'Single dose in water, review in 3 weeks',
          adviceDiet: 'Avoid late nights, take regular warm meals',
        ),
        followUp: HomeopathyFollowUp(
          responseRating: 'Marked Improvement',
          heringsLawDirection: 'Inside-outward (headache stopped, mild skin itch appeared)',
          clinicalChangesObserved: 'Headache episodes reduced from 2/week to zero in 3 weeks',
          nextPrescriptionPlan: 'Continue Sac Lac (Placebo) single dose weekly',
          nextFollowUpDate: now.add(const Duration(days: 21)),
          followUpNotes: 'Patient advised to continue current diet',
        ),
        additionalNotes: 'Patient advised to keep headache trigger diary',
        createdAt: now,
        updatedAt: now,
      );

      final map = sheet.toMap();
      expect(map['id'], 'case-001');
      expect(map['patientId'], 'pat-001');
      expect(map['doctorId'], 'doc-001');
      expect(map['caseType'], 'chronic');
      expect(map['isCompleted'], 1);
      expect(map['chiefProblem'], 'Chronic Migraine & Acid Reflux');

      final reconstructed = HomeopathyCaseSheet.fromMap(map);
      expect(reconstructed.id, sheet.id);
      expect(reconstructed.overview.chiefProblem, sheet.overview.chiefProblem);
      expect(reconstructed.overview.referralSource, 'Dr. Sharma Referral');
      expect(reconstructed.overview.patientPerceivedCause, 'Severe work grief and mental exhaustion');
      expect(reconstructed.chiefComplaint.location, 'Right temporal region');
      expect(reconstructed.generalSymptoms.thermalState,
          HomeopathyThermalState.chilly);
      expect(reconstructed.generalSymptoms.thirstStyle, 'Large gulps at long intervals');
      expect(reconstructed.generalSymptoms.perspirationLocation, 'Occiput and neck');
      expect(reconstructed.physicalSymptoms.feverPeriodicity, 'Periodic every 7 days');
      expect(reconstructed.physicalSymptoms.coughType, 'Dry spasmodic cough');
      expect(reconstructed.mentalEmotional.familyDynamics, 'Supportive nuclear family');
      expect(reconstructed.mentalEmotional.reactionToDisease, 'Fears death during severe acute migraines');
      expect(reconstructed.prescriptionNotes.prescribedRemedy,
          'Lycopodium Clavatum');
      expect(reconstructed.prescriptionNotes.totalityOfSymptoms, contains('Right-sided temporal headache'));
      expect(reconstructed.followUp.responseRating, 'Marked Improvement');
      expect(reconstructed.completedSectionsCount(isFemale: true), 15);
      expect(reconstructed.isCompleted, true);
    });
  });

  group('Homeopathy SQLite Database Integration Tests', () {
    test('creates homeopathy table and executes full CRUD with new fields', () async {
      final dbPath = '${Directory.systemTemp.path}/crudoc_homeopathy_test_${DateTime.now().microsecondsSinceEpoch}.db';

      final database = await sqflite_ffi.databaseFactoryFfi.openDatabase(
        dbPath,
        options: sqflite_common.OpenDatabaseOptions(version: 1),
      );
      addTearDown(() async {
        await database.close();
        final file = File(dbPath);
        if (await file.exists()) {
          await file.delete();
        }
      });

      final localDb = WindowsDatabase(database);

      // Create table using the exact schema
      await localDb.execute('''
        CREATE TABLE IF NOT EXISTS homeopathy_case_sheets (
          id TEXT PRIMARY KEY,
          patientId TEXT NOT NULL DEFAULT '',
          doctorId TEXT NOT NULL DEFAULT '',
          caseDate INTEGER NOT NULL,
          caseType TEXT NOT NULL DEFAULT 'chronic',
          isCompleted INTEGER NOT NULL DEFAULT 0,
          chiefProblem TEXT NOT NULL DEFAULT '',
          priority TEXT NOT NULL DEFAULT 'normal',
          consultationReason TEXT NOT NULL DEFAULT '',
          referralSource TEXT NOT NULL DEFAULT '',
          priorHomeopathyExperience TEXT NOT NULL DEFAULT '',
          patientPerceivedCause TEXT NOT NULL DEFAULT '',
          overview TEXT NOT NULL DEFAULT '{}',
          chiefComplaint TEXT NOT NULL DEFAULT '{}',
          modalities TEXT NOT NULL DEFAULT '{}',
          generalSymptoms TEXT NOT NULL DEFAULT '{}',
          physicalSymptoms TEXT NOT NULL DEFAULT '{}',
          femaleReproductive TEXT NOT NULL DEFAULT '{}',
          mentalEmotional TEXT NOT NULL DEFAULT '{}',
          dreamsSleep TEXT NOT NULL DEFAULT '{}',
          sexualHistory TEXT NOT NULL DEFAULT '{}',
          medicalHistory TEXT NOT NULL DEFAULT '{}',
          physicalExamination TEXT NOT NULL DEFAULT '{}',
          investigations TEXT NOT NULL DEFAULT '{}',
          peculiarSymptoms TEXT NOT NULL DEFAULT '',
          prescriptionNotes TEXT NOT NULL DEFAULT '{}',
          repertorizationNotes TEXT NOT NULL DEFAULT '',
          miasmaticTendency TEXT NOT NULL DEFAULT '',
          suggestedRemedies TEXT NOT NULL DEFAULT '',
          followUp TEXT NOT NULL DEFAULT '{}',
          additionalNotes TEXT NOT NULL DEFAULT '',
          caseSheetCategory TEXT NOT NULL DEFAULT 'general',
          childhoodHistory TEXT NOT NULL DEFAULT '{}',
          childrenCaseSheet TEXT NOT NULL DEFAULT '{}',
          femaleEndocrine TEXT NOT NULL DEFAULT '{}',
          acuteSheet TEXT NOT NULL DEFAULT '{}',
          createdAt INTEGER NOT NULL,
          updatedAt INTEGER NOT NULL,
          syncStatus TEXT NOT NULL DEFAULT 'synced',
          pendingDelete INTEGER NOT NULL DEFAULT 0,
          lastSyncedAt INTEGER
        )
      ''');

      final now = DateTime.now();
      final sheet = HomeopathyCaseSheet.empty(
        id: 'homeo-test-101',
        patientId: 'patient-505',
        doctorId: 'doctor-707',
      ).copyWith(
        isCompleted: true,
        overview: HomeopathyCaseOverview(
          caseType: HomeopathyCaseType.acute,
          caseDate: now,
          chiefProblem: 'Acute High Fever with Restlessness',
          referralSource: 'Walk-in',
          priorHomeopathyExperience: 'First time homeopathy patient',
          patientPerceivedCause: 'Chilled by air conditioning after heavy workout',
        ),
        chiefComplaint: const HomeopathyChiefComplaint(
          complaint: 'High fever and anxiety',
        ),
        generalSymptoms: const HomeopathyGeneralSymptoms(
          thirstStyle: 'Thirsty for large gulps of ice cold water frequently',
          perspirationLocation: 'Head and forehead profuse',
          perspirationOdour: 'Sour',
          thermalState: HomeopathyThermalState.hot,
        ),
        physicalSymptoms: const HomeopathyPhysicalSymptoms(
          feverChillStage: 'Sudden shaking chills at 3 PM',
          feverHeatStage: 'Intense dry burning heat, red flushed face',
          feverSweatStage: 'Sweat breaks out after 2 hours with relief',
          feverPeriodicity: 'Spikes every afternoon',
          coughType: 'Dry hacking cough',
          sputumDetails: 'Scanty mucus',
          coughTasteInMouth: 'Bitter taste',
          digestiveStoolDetails: 'Loose watery stool with sudden urgency',
          headVertigoSymptoms: 'Throbbing frontal headache, worse stooping',
        ),
        mentalEmotional: const HomeopathyMentalEmotional(
          reactionToDisease: 'Fears death during fever peak, high panic',
          dullnessVsRestlessness: 'Continuous anxious tossing in bed',
          facialExpression: 'Frightened facies, dilated pupils',
          mentalShiftSinceIllness: 'Usually calm, now highly anxious',
          familyDynamics: 'Living with supportive spouse',
          colleaguesWorkStress: 'Recent workload deadline',
        ),
        prescriptionNotes: const HomeopathyPrescriptionNotes(
          prescribedRemedy: 'Aconitum Napellus',
          potency: '200C',
          repetitionScale: 'Dose every 2 hours in water until sweat occurs',
          totalityOfSymptoms: 'Sudden high fever + intense restlessness + fear of death + unquenchable thirst',
          differentialRemedies: 'Belladonna (red face, no thirst), Arsenicum (chilly, small sips)',
        ),
        followUp: HomeopathyFollowUp(
          responseRating: 'Marked Improvement',
          heringsLawDirection: 'Inside-outward (fever subsided, perspiration became free and natural)',
          clinicalChangesObserved: 'Temperature normalized to 98.4 F within 4 hours, anxiety completely vanished',
          nextPrescriptionPlan: 'Placebo (Sac Lac) single dose, observe',
          followUpNotes: 'Patient advised to rest and stay hydrated',
        ),
      );

      final row = Map<String, dynamic>.from(sheet.toMap());
      row['syncStatus'] = 'pending';
      row['pendingDelete'] = 0;

      // Insert
      final insertResult = await localDb.insert(
        'homeopathy_case_sheets',
        row,
        conflictAlgorithm: LocalConflictAlgorithm.replace,
      );
      expect(insertResult, isNotNull);

      // Query
      final queriedRows = await localDb.query(
        'homeopathy_case_sheets',
        where: 'patientId = ? AND doctorId = ? AND pendingDelete = 0',
        whereArgs: ['patient-505', 'doctor-707'],
      );
      expect(queriedRows.length, 1);

      final retrieved = HomeopathyCaseSheet.fromMap(queriedRows.first);
      expect(retrieved.id, 'homeo-test-101');
      expect(retrieved.overview.chiefProblem, 'Acute High Fever with Restlessness');
      expect(retrieved.overview.patientPerceivedCause, 'Chilled by air conditioning after heavy workout');
      expect(retrieved.generalSymptoms.thirstStyle, 'Thirsty for large gulps of ice cold water frequently');
      expect(retrieved.generalSymptoms.perspirationLocation, 'Head and forehead profuse');
      expect(retrieved.physicalSymptoms.feverChillStage, 'Sudden shaking chills at 3 PM');
      expect(retrieved.physicalSymptoms.feverHeatStage, 'Intense dry burning heat, red flushed face');
      expect(retrieved.physicalSymptoms.feverPeriodicity, 'Spikes every afternoon');
      expect(retrieved.physicalSymptoms.digestiveStoolDetails, 'Loose watery stool with sudden urgency');
      expect(retrieved.mentalEmotional.reactionToDisease, 'Fears death during fever peak, high panic');
      expect(retrieved.mentalEmotional.dullnessVsRestlessness, 'Continuous anxious tossing in bed');
      expect(retrieved.prescriptionNotes.prescribedRemedy, 'Aconitum Napellus');
      expect(retrieved.prescriptionNotes.totalityOfSymptoms, contains('Sudden high fever'));
      expect(retrieved.followUp.responseRating, 'Marked Improvement');
      expect(retrieved.followUp.heringsLawDirection, contains('Inside-outward'));
      expect(retrieved.followUp.nextPrescriptionPlan, 'Placebo (Sac Lac) single dose, observe');

      // Update follow-up
      final updatedSheet = retrieved.copyWith(
        followUp: retrieved.followUp.copyWith(
          responseRating: 'Cured',
          clinicalChangesObserved: 'Patient completely symptom-free 24 hours post-treatment',
        ),
      );
      final updatedRow = Map<String, dynamic>.from(updatedSheet.toMap());
      await localDb.update(
        'homeopathy_case_sheets',
        updatedRow,
        where: 'id = ?',
        whereArgs: [updatedSheet.id],
      );

      final postUpdateRows = await localDb.query(
        'homeopathy_case_sheets',
        where: 'id = ?',
        whereArgs: ['homeo-test-101'],
      );
      final postUpdateSheet = HomeopathyCaseSheet.fromMap(postUpdateRows.first);
      expect(postUpdateSheet.followUp.responseRating, 'Cured');
      expect(postUpdateSheet.followUp.clinicalChangesObserved, contains('completely symptom-free'));
    });
  });

  group('HomeopathyVoiceScribeService Parsing & Extraction Tests', () {
    test('parses raw Gemini JSON into structured HomeopathyCaseSheet with all sections', () {
      final baseSheet = HomeopathyCaseSheet.empty(
        id: 'case-scribe-001',
        patientId: 'patient-300',
        doctorId: 'doctor-500',
      );

      const mockGeminiJson = '''
      ```json
      {
        "overview": {
          "caseType": "acute",
          "chiefProblem": "Sudden High Fever with Severe Dry Cough",
          "consultationReason": "Acute illness since yesterday",
          "referralSource": "Family Doctor referral",
          "patientPerceivedCause": "Getting drenched in sudden rain"
        },
        "chiefComplaint": {
          "complaint": "Violent continuous coughing with fever and chest soreness",
          "location": "Larynx, trachea, and sternum",
          "sensationDescription": "Raw burning sensation as if larynx is scraped",
          "onset": "Sudden onset last evening",
          "duration": "24 hours",
          "frequency": "Paroxysms every 15-20 minutes",
          "triggeringCauses": "Exposure to cold draft"
        },
        "modalities": {
          "aggravatingFactors": "Cold air, talking, lying down flat, midnight",
          "amelioratingFactors": "Warm drinks, sitting erect",
          "timePatterns": "Peak aggravation at 11 PM and 2 AM"
        },
        "generalSymptoms": {
          "thermalState": "chilly",
          "appetite": "Complete loss of appetite",
          "thirst": "Thirst for warm tea",
          "thirstStyle": "Small sips frequently",
          "cravingsDesires": ["Warm water", "Lemon tea"],
          "perspiration": "Scanty dry skin, no perspiration yet",
          "perspirationLocation": "Forehead only"
        },
        "physicalSymptoms": {
          "respiratory": "Oppression in chest, shallow rapid breathing",
          "coughType": "Dry, hard, barking cough",
          "sputumDetails": "Very scanty thick mucus",
          "coughTasteInMouth": "Bitter taste on tongue",
          "feverChillStage": "Shivers down the back at 4 PM",
          "feverHeatStage": "Burning dry heat without sweat",
          "headVertigoSymptoms": "Congestive bursting frontal headache"
        },
        "mentalEmotional": {
          "disposition": "Highly restless, impatient, irritable",
          "fears": ["Fear of suffocation", "Fear of death"],
          "reactionToDisease": "Anxious tossing in bed, despairs of ease",
          "dullnessVsRestlessness": "Restless tossing, unable to stay still in one position",
          "facialExpression": "Anxious pinched facies, flushed cheeks",
          "familyDynamics": "Spouse attending patient at bedside"
        },
        "prescriptionNotes": {
          "prescribedRemedy": "Aconitum Napellus",
          "potency": "30C",
          "repetitionScale": "Dose every 1 hour in water for 4 doses, then review",
          "totalityOfSymptoms": "Sudden violent onset after cold draft + high fever without sweat + dry barking cough + extreme restlessness & anxiety",
          "differentialRemedies": "Belladonna (throbbing head, red face), Bryonia (worse from least motion, dry lips)"
        },
        "followUp": {
          "responseRating": "Pending observation",
          "nextPrescriptionPlan": "Wait and watch for perspiration"
        }
      }
      ```
      ''';

      final service = HomeopathyVoiceScribeService.instance;
      final parsed = service.parseJsonIntoSheet(mockGeminiJson, existingSheet: baseSheet);

      // Verify Overview
      expect(parsed.overview.caseType, HomeopathyCaseType.acute);
      expect(parsed.overview.chiefProblem, 'Sudden High Fever with Severe Dry Cough');
      expect(parsed.overview.referralSource, 'Family Doctor referral');
      expect(parsed.overview.patientPerceivedCause, 'Getting drenched in sudden rain');

      // Verify Chief Complaint
      expect(parsed.chiefComplaint.complaint, 'Violent continuous coughing with fever and chest soreness');
      expect(parsed.chiefComplaint.location, 'Larynx, trachea, and sternum');
      expect(parsed.chiefComplaint.sensationDescription, 'Raw burning sensation as if larynx is scraped');
      expect(parsed.chiefComplaint.onset, 'Sudden onset last evening');

      // Verify Modalities
      expect(parsed.modalities.aggravatingFactors, contains('Cold air'));
      expect(parsed.modalities.amelioratingFactors, contains('Warm drinks'));
      expect(parsed.modalities.timePatterns, contains('11 PM'));

      // Verify Generals
      expect(parsed.generalSymptoms.thermalState, HomeopathyThermalState.chilly);
      expect(parsed.generalSymptoms.thirstStyle, 'Small sips frequently');
      expect(parsed.generalSymptoms.cravingsDesires, contains('Warm water'));

      // Verify Physicals & Acute Fever Stages
      expect(parsed.physicalSymptoms.coughType, 'Dry, hard, barking cough');
      expect(parsed.physicalSymptoms.feverChillStage, 'Shivers down the back at 4 PM');
      expect(parsed.physicalSymptoms.feverHeatStage, 'Burning dry heat without sweat');
      expect(parsed.physicalSymptoms.headVertigoSymptoms, 'Congestive bursting frontal headache');

      // Verify Mental & Emotional
      expect(parsed.mentalEmotional.fears, contains('Fear of suffocation'));
      expect(parsed.mentalEmotional.fears, contains('Fear of death'));
      expect(parsed.mentalEmotional.reactionToDisease, contains('Anxious tossing'));
      expect(parsed.mentalEmotional.dullnessVsRestlessness, contains('Restless tossing'));

      // Verify Prescription & Totality
      expect(parsed.prescriptionNotes.prescribedRemedy, 'Aconitum Napellus');
      expect(parsed.prescriptionNotes.potency, '30C');
      expect(parsed.prescriptionNotes.totalityOfSymptoms, contains('Sudden violent onset'));
      expect(parsed.prescriptionNotes.differentialRemedies, contains('Belladonna'));
    });

    test('preserves existing case sheet fields when incoming voice JSON omits them', () {
      final base = HomeopathyCaseSheet.empty(
        id: 'case-scribe-002',
        patientId: 'patient-400',
        doctorId: 'doctor-600',
      );
      final baseSheet = base.copyWith(
        overview: base.overview.copyWith(
          chiefProblem: 'Original Chronic Problem',
          referralSource: 'Original Referral',
        ),
      );

      const partialJson = '''
      {
        "chiefComplaint": {
          "complaint": "New acute symptom described in voice"
        }
      }
      ''';

      final service = HomeopathyVoiceScribeService.instance;
      final parsed = service.parseJsonIntoSheet(partialJson, existingSheet: baseSheet);

      // Existing data preserved
      expect(parsed.overview.chiefProblem, 'Original Chronic Problem');
      expect(parsed.overview.referralSource, 'Original Referral');

      // New voice data populated
      expect(parsed.chiefComplaint.complaint, 'New acute symptom described in voice');
    });
  });

  group('Homeopathy 4 Clinical Questionnaires Extended Models Tests', () {
    test('category enum correctly resolves from various string formats', () {
      expect(HomeopathyCaseSheetCategory.fromString('general'),
          HomeopathyCaseSheetCategory.general);
      expect(HomeopathyCaseSheetCategory.fromString('children'),
          HomeopathyCaseSheetCategory.children);
      expect(HomeopathyCaseSheetCategory.fromString('femaleEndocrine'),
          HomeopathyCaseSheetCategory.femaleEndocrine);
      expect(HomeopathyCaseSheetCategory.fromString('female_endocrine'),
          HomeopathyCaseSheetCategory.femaleEndocrine);
      expect(HomeopathyCaseSheetCategory.fromString('acute'),
          HomeopathyCaseSheetCategory.acute);
      expect(HomeopathyCaseSheetCategory.fromString(null),
          HomeopathyCaseSheetCategory.general);
    });

    test('serializes and deserializes extended sections accurately', () {
      const childhood = HomeopathyChildhoodHistory(
        childhoodNature: 'Shy and reserved',
        childhoodHabits: 'Nail biting',
        childhoodFears: 'Dark and dogs',
        childhoodDreams: 'Monsters chasing',
        childhoodRelationships: 'Close to mother',
        childhoodSensitivities: 'Cries easily when scolded',
      );

      const childrenSheet = HomeopathyChildrenCaseSheet(
        coldOrHeatSensitive: 'Very chilly, easily catches colds',
        behaviorWhenUpset: 'Sulks in corner, stubborn',
        whatMakesHappy: 'Storytelling, drawing',
        schoolBehavior: 'Attentive, quiet',
        graspingIntelligenceScore: 8,
        childTypeDescription: 'Delicate, fair, easily fatigued',
        vaccinationHistory: 'Mild fever after MMR',
        favoriteSportActivity: 'Swimming',
        attitudeToParents: 'Affectionate',
      );

      const endocrine = HomeopathyFemaleEndocrine(
        medicalDiagnosis: 'Hypothyroidism (Hashimoto\'s)',
        howAndWhenStarted: 'After pregnancy 3 years ago',
        physiologicalCauseTrigger: 'Postpartum hormone shift',
        emotionalTriggers: 'Severe grief after parent demise',
        diseaseManifestationLocation: 'Thyroid gland, neck fullness',
        stagesOfLife: 'Menarche at 14, two full-term pregnancies',
        physicalWeakness: 'Extreme morning fatigue, puffy face',
      );

      const acute = HomeopathyAcuteSheet(
        detailedComplaint: 'Sudden onset high fever at midnight with delirium',
        causeOfComplaint: 'Exposure to chilling north wind',
        whatMakesWorse: 'Motion, noise, bright light',
        whatMakesBetter: 'Lying in dark quiet room, cold compress',
        mentalConditionDuringSuffering: 'High restlessness and panic',
        waterRequirement: 'Unquenchable thirst for cold water in large gulps',
        sweatDetails: 'Scanty sweat during fever',
        acuteFeverDetails: 'Chill at 10 PM followed by burning heat at 1 AM',
        coughRespirationDetail: 'Dry whistling cough, throat constriction',
        looseDryCoughDetails: 'Dry barking',
        bodyPainDetails: 'Sore bruised pain all over',
      );

      final now = DateTime.now();
      final caseSheet = HomeopathyCaseSheet(
        id: 'case-ext-001',
        patientId: 'patient-ext-100',
        doctorId: 'doctor-ext-200',
        overview: HomeopathyCaseOverview(caseDate: now),
        chiefComplaint: const HomeopathyChiefComplaint(),
        modalities: const HomeopathyModalities(),
        generalSymptoms: const HomeopathyGeneralSymptoms(
          hungerTime: '11 AM hunger sinking sensation',
          hungerReaction: 'Severe headache if meal is delayed',
          eatingSpeed: 'Eats hastily in hurry',
          thirstTime: 'Night 2 AM thirst',
          tasteChanges: 'Bitter metallic taste in morning',
        ),
        physicalSymptoms: const HomeopathyPhysicalSymptoms(),
        femaleReproductive: const HomeopathyFemaleHistory(),
        mentalEmotional: const HomeopathyMentalEmotional(
          upsetWorryTriggers: 'Injustice and family disharmony',
          fearDetails: 'Fear of narrow spaces and elevators',
          introvertExtrovert: 'Introvert, keeps grief to oneself',
          greatestGrief: 'Loss of father in 2020',
        ),
        dreamsSleep: const HomeopathyDreamsSleep(
          sleepPosture: 'Lies on right side with arms folded',
          sleepPositionRestrictions: 'Cannot lie on left side due to heart palpitations',
          sleepBehaviors: 'Grinds teeth in sleep',
          childhoodDreams: 'Falling from cliff',
        ),
        sexualHistory: const HomeopathySexualHistory(),
        medicalHistory: const HomeopathyMedicalHistory(),
        physicalExamination: const HomeopathyPhysicalExam(),
        investigations: const HomeopathyInvestigations(),
        peculiarSymptoms: const HomeopathyPeculiarSymptoms(),
        prescriptionNotes: const HomeopathyPrescriptionNotes(),
        caseSheetCategory: HomeopathyCaseSheetCategory.femaleEndocrine,
        childhoodHistory: childhood,
        childrenCaseSheet: childrenSheet,
        femaleEndocrine: endocrine,
        acuteSheet: acute,
        createdAt: now,
        updatedAt: now,
      );

      // Verify toMap & fromMap
      final map = caseSheet.toMap();
      final restored = HomeopathyCaseSheet.fromMap(map);

      expect(restored.caseSheetCategory, HomeopathyCaseSheetCategory.femaleEndocrine);
      expect(restored.childhoodHistory.childhoodNature, 'Shy and reserved');
      expect(restored.childhoodHistory.childhoodFears, 'Dark and dogs');
      expect(restored.childrenCaseSheet.coldOrHeatSensitive, 'Very chilly, easily catches colds');
      expect(restored.childrenCaseSheet.graspingIntelligenceScore, 8);
      expect(restored.femaleEndocrine.medicalDiagnosis, contains('Hashimoto\'s'));
      expect(restored.femaleEndocrine.stagesOfLife, contains('Menarche at 14'));
      expect(restored.acuteSheet.detailedComplaint, contains('Sudden onset high fever'));
      expect(restored.acuteSheet.waterRequirement, contains('large gulps'));
      expect(restored.generalSymptoms.hungerTime, '11 AM hunger sinking sensation');
      expect(restored.generalSymptoms.tasteChanges, 'Bitter metallic taste in morning');
      expect(restored.mentalEmotional.upsetWorryTriggers, 'Injustice and family disharmony');
      expect(restored.dreamsSleep.sleepPosture, contains('right side'));
      expect(restored.completedSectionsCount(isFemale: true), greaterThanOrEqualTo(5));
    });
  });
}

