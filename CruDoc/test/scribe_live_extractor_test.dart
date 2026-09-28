import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/scribe/services/scribe_live_extractor.dart';

void main() {
  const extractor = ScribeLiveExtractor();

  group('ScribeLiveExtractor', () {
    test('detects field cues for instant pending dissolve', () {
      final cues = extractor.detectFieldCues('Patient has severe right shoulder pain and stiffness');
      expect(cues, contains('chiefComplaint'));
      expect(cues, contains('symptoms'));
      expect(cues, contains('painNow'));
    });

    test('extracts Chief Complaint accurately', () {
      final res = extractor.extract(
        'Doctor: What is the main problem? Patient: Chief complaint is right shoulder pain for 3 weeks.',
      );
      expect(res.chiefComplaint, equals('Right shoulder pain for 3 weeks'));
    });

    test('extracts Symptoms and Anatomical locations', () {
      final res = extractor.extract(
        'Patient reports severe knee pain with swelling and morning stiffness in the joint.',
      );
      expect(res.symptoms, contains('Knee Pain'));
      expect(res.symptoms, contains('Swelling'));
      expect(res.symptoms, contains('Morning Stiffness'));
    });

    test('extracts Clinical Impression and Diagnoses', () {
      final res = extractor.extract(
        'On clinical examination, impression is cervical spondylosis and frozen shoulder.',
      );
      expect(res.diagnoses, contains('Cervical Spondylosis'));
      expect(res.diagnoses, contains('Frozen Shoulder'));
    });

    test('extracts Medications with dosage and instructions', () {
      final res = extractor.extract(
        'I am prescribing Paracetamol 650 mg twice daily and Pantoprazole 40 mg before breakfast with Volini gel.',
      );
      expect(res.medicines.map((m) => m.name), contains('Paracetamol'));
      expect(res.medicines.map((m) => m.name), contains('Pantoprazole'));
      expect(res.medicines.map((m) => m.name), contains('Volini'));
    });

    test('extracts Vitals (BP, Temp, Pulse)', () {
      final res = extractor.extract(
        'Vitals recorded today: BP 120/80, temperature 99.4 F, pulse 76 bpm.',
      );
      expect(res.bp, equals('120/80 mmHg'));
      expect(res.temp, equals('99.4 °F'));
      expect(res.pulse, equals('76 bpm'));
    });

    test('extracts Pain details (NPRS, Location, Nature)', () {
      final res = extractor.extract(
        'Current pain score is 7 out of 10, worst pain reached 9, localized to right knee with sharp shooting pain.',
      );
      expect(res.painNow, equals('7/10'));
      expect(res.painWorst, equals('9/10'));
      expect(res.painLocation, equals('Right Knee'));
      expect(res.painNature, equals('Sharp shooting pain'));
    });

    test('extracts Education & Advice', () {
      final res = extractor.extract(
        'Advice for home: avoid forward bending, apply hot pack twice daily, and start gentle walking.',
      );
      expect(res.advice, contains('Avoid forward bending'));
      expect(res.advice, contains('Apply hot pack twice daily'));
    });

    test('extracts Follow-up duration', () {
      final res = extractor.extract(
        'Come back for follow up in 5 days.',
      );
      expect(res.followUpDate, isNotNull);
    });

    test('understands conversational multi-turn context (QA resolution)', () {
      final res = extractor.extract('''
Doctor: What is the intensity of the pain? Is it about 5 or 10 out of 10, what will you rate it?
Patient: I think I will say 7 on 10. I have severe pain on my right side for 10 days. I haven't been able to walk properly.
''');
      expect(res.painNow, equals('7/10'));
      expect(res.chiefComplaint, contains('Severe pain'));
      expect(res.chiefComplaint, contains('10 days'));
      expect(res.painLocation, equals('Right Side'));
      expect(res.symptoms, contains('Unable To Walk Properly'));
    });

    test('understands clinical negation (excludes negated symptoms and diagnoses)', () {
      final res = extractor.extract(
        'Patient presents with severe joint stiffness. Denies any fever, chills, or headache. Rules out fracture.',
      );
      expect(res.symptoms, contains('Joint Stiffness'));
      expect(res.symptoms, isNot(contains('Fever')));
      expect(res.symptoms, isNot(contains('Chills')));
      expect(res.symptoms, isNot(contains('Headache')));
      expect(res.diagnoses, isNot(contains('Fracture')));
    });

    test('understands aggravating and easing factors from dialogue context', () {
      final res = extractor.extract('''
Doctor: What makes the pain worse? Does anything increase it?
Patient: The pain is worse with forward bending and prolonged sitting.
Doctor: And what gives you relief?
Patient: Taking rest and applying a hot water bag gives relief.
''');
      expect(res.aggravating, contains('Forward Bending'));
      expect(res.aggravating, contains('Prolonged Sitting'));
      expect(res.easing, contains('Rest'));
      expect(res.easing, contains('Hot Water Fermentation'));
    });

    test('understands onset mechanism, past medical history, and patient goals', () {
      final res = extractor.extract('''
Doctor: When and how did this start?
Patient: Started 10 days ago after lifting heavy boxes.
Doctor: Any past medical history of diabetes, hypertension or asthma?
Patient: I am a known case of Type 2 Diabetes for 5 years, no history of hypertension.
Doctor: What are your main goals for therapy?
Patient: I want to return to playing cricket and climb stairs without pain.
''');
      expect(res.onset, contains('Started 10 days ago after lifting heavy boxes'));
      expect(res.history, contains('Type 2 Diabetes Mellitus'));
      expect(res.history, isNot(contains('Hypertension')));
      expect(res.patientGoals, contains('Return to playing cricket'));
    });
  });
}
