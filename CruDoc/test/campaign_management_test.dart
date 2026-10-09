import 'package:flutter_test/flutter_test.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/campaigns/data/models/campaign_enums.dart';
import 'package:doctor_management_app/features/campaigns/data/models/campaign_model.dart';
import 'package:doctor_management_app/features/campaigns/data/models/campaign_recipient_log.dart';
import 'package:doctor_management_app/features/campaigns/data/repo/campaign_repository.dart';
import 'package:doctor_management_app/features/campaigns/data/services/campaign_audience_helper.dart';
import 'package:doctor_management_app/features/campaigns/data/services/campaign_dispatch_service.dart';
import 'package:doctor_management_app/features/messaging/data/services/gmail_auth_service.dart';
import 'package:doctor_management_app/features/messaging/data/services/gmail_send_service.dart';

void main() {
  group('Campaign Model & Enum Tests', () {
    test('CampaignModel serializes and deserializes accurately with all fields', () {
      final now = DateTime(2026, 8, 22, 10, 30);
      final campaign = CampaignModel(
        id: 'camp-101',
        doctorId: 'doc-456',
        title: 'Free Diabetes Screening Camp',
        message: 'Dear {{patient_name}}, join us this Sunday at {{clinic_name}}.',
        category: CampaignCategory.checkupCamp,
        channels: CampaignChannel.both,
        audienceType: AudienceType.byDiagnosis,
        targetFilters: {'condition': 'Diabetes'},
        selectedPatientIds: ['p1', 'p2'],
        mediaUrl: 'https://example.com/banner.png',
        status: CampaignStatus.completed,
        scheduledAt: now.add(const Duration(days: 2)),
        createdAt: now,
        updatedAt: now,
        totalRecipients: 50,
        emailsSent: 45,
        emailsFailed: 5,
        whatsAppSent: 48,
        whatsAppFailed: 2,
        metadata: {'author': 'admin'},
      );

      final map = campaign.toMap();
      expect(map['title'], 'Free Diabetes Screening Camp');
      expect(map['category'], 'checkupCamp');
      expect(map['channels'], 'both');
      expect(map['audienceType'], 'byDiagnosis');
      expect(map['totalRecipients'], 50);
      expect(map['emailsSent'], 45);
      expect(map['whatsAppSent'], 48);

      final reconstructed = CampaignModel.fromMap(map, id: 'camp-101');
      expect(reconstructed.id, 'camp-101');
      expect(reconstructed.doctorId, 'doc-456');
      expect(reconstructed.title, 'Free Diabetes Screening Camp');
      expect(reconstructed.category, CampaignCategory.checkupCamp);
      expect(reconstructed.channels, CampaignChannel.both);
      expect(reconstructed.audienceType, AudienceType.byDiagnosis);
      expect(reconstructed.targetFilters['condition'], 'Diabetes');
      expect(reconstructed.selectedPatientIds, ['p1', 'p2']);
      expect(reconstructed.totalRecipients, 50);
      expect(reconstructed.totalSent, 93); // 45 + 48
      expect(reconstructed.totalFailed, 7); // 5 + 2
      expect(reconstructed.successRate, closeTo(93.0, 0.1));
    });

    test('CampaignModel handles null/default fallbacks gracefully', () {
      final campaign = CampaignModel.fromMap({}, id: 'fallback-id');
      expect(campaign.id, 'fallback-id');
      expect(campaign.title, '');
      expect(campaign.category, CampaignCategory.generalAnnouncement);
      expect(campaign.channels, CampaignChannel.both);
      expect(campaign.status, CampaignStatus.draft);
      expect(campaign.totalRecipients, 0);
      expect(campaign.successRate, 0.0);
    });

    test('CampaignRecipientLog serializes and evaluates delivery status correctly', () {
      final now = DateTime(2026, 8, 22, 11, 0);
      final log = CampaignRecipientLog(
        id: 'rec-1',
        campaignId: 'camp-101',
        doctorId: 'doc-456',
        patientId: 'pat-99',
        patientName: 'Amit Verma',
        email: 'amit@example.com',
        phone: '+919876543210',
        emailStatus: RecipientDeliveryStatus.sent,
        whatsAppStatus: RecipientDeliveryStatus.failed,
        emailMessageId: 'msg-12345',
        whatsAppError: 'Invalid WhatsApp format',
        dispatchedAt: now,
        updatedAt: now,
      );

      expect(log.isSuccessful, isTrue); // Email was sent
      expect(log.hasFailed, isTrue); // WhatsApp failed
      expect(log.formattedDispatchedAt, isNotEmpty);

      final map = log.toMap();
      final fromMap = CampaignRecipientLog.fromMap(map, id: 'rec-1');
      expect(fromMap.patientName, 'Amit Verma');
      expect(fromMap.emailStatus, RecipientDeliveryStatus.sent);
      expect(fromMap.whatsAppStatus, RecipientDeliveryStatus.failed);
      expect(fromMap.whatsAppError, 'Invalid WhatsApp format');
    });

    test('CampaignRecipientLog carries simulated flags through serialization', () {
      final now = DateTime(2026, 8, 22, 11, 0);
      final log = CampaignRecipientLog(
        id: 'rec-2',
        campaignId: 'camp-101',
        doctorId: 'doc-456',
        patientId: 'pat-1',
        patientName: 'Sim Patient',
        emailStatus: RecipientDeliveryStatus.sent,
        whatsAppStatus: RecipientDeliveryStatus.sent,
        emailSimulated: true,
        whatsAppSimulated: true,
        dispatchedAt: now,
        updatedAt: now,
      );

      expect(log.isSimulated, isTrue);

      final roundTripped = CampaignRecipientLog.fromMap(
        log.toMap(),
        id: 'rec-2',
      );
      expect(roundTripped.emailSimulated, isTrue);
      expect(roundTripped.whatsAppSimulated, isTrue);
      expect(roundTripped.isSimulated, isTrue);

      // Legacy documents without the field default to false (not simulated).
      final legacy = CampaignRecipientLog.fromMap(
        {'patientName': 'Legacy', 'emailStatus': 'delivered'},
        id: 'rec-legacy',
      );
      expect(legacy.emailSimulated, isFalse);
      expect(legacy.whatsAppSimulated, isFalse);
      expect(legacy.isSimulated, isFalse);
    });
  });

  group('Campaign Audience Helper & Personalization Tests', () {
    late List<Patient> samplePatients;

    setUp(() {
      samplePatients = [
        Patient(
          id: 'p1',
          firstName: 'Rahul',
          lastName: 'Sharma',
          phone: '+919876543210',
          email: 'rahul@example.com',
          gender: 'Male',
          dateOfBirth: DateTime(1960, 5, 10), // ~66 years old (Senior)
          diagnosis: ['Type 2 Diabetes', 'Hypertension'],
          packageBalance: 0,
          isArchived: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Patient(
          id: 'p2',
          firstName: 'Priya',
          lastName: 'Patel',
          phone: '9876543211',
          email: 'priya@example.com',
          gender: 'Female',
          dateOfBirth: DateTime(1995, 8, 20), // ~31 years old (Adult)
          diagnosis: ['Asthma'],
          packageBalance: 0,
          isArchived: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Patient(
          id: 'p3',
          firstName: 'Archived',
          lastName: 'Patient',
          phone: '9876543212',
          email: 'archived@example.com',
          gender: 'Male',
          dateOfBirth: DateTime(1980, 1, 1),
          diagnosis: ['Diabetes'],
          packageBalance: 0,
          isArchived: true, // Should always be excluded
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Patient(
          id: 'p4',
          firstName: 'Aarav',
          lastName: 'Singh',
          phone: '9876543213',
          email: '',
          gender: 'Male',
          dateOfBirth: DateTime(2015, 3, 15), // ~11 years old (Child)
          diagnosis: ['Seasonal Allergy'],
          packageBalance: 0,
          isArchived: false,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];
    });

    test('AudienceType.all returns all active patients and excludes archived', () {
      final result = CampaignAudienceHelper.filterPatients(
        allPatients: samplePatients,
        audienceType: AudienceType.all,
      );
      expect(result.length, 3);
      expect(result.any((p) => p.isArchived), isFalse);
    });

    test('AudienceType.byDiagnosis filters matching conditions correctly', () {
      final diabeticPatients = CampaignAudienceHelper.filterPatients(
        allPatients: samplePatients,
        audienceType: AudienceType.byDiagnosis,
        filters: {'condition': 'Diabetes'},
      );
      expect(diabeticPatients.length, 1);
      expect(diabeticPatients.first.fullName, 'Rahul Sharma');

      final asthmaPatients = CampaignAudienceHelper.filterPatients(
        allPatients: samplePatients,
        audienceType: AudienceType.byDiagnosis,
        filters: {'condition': 'asthma'},
      );
      expect(asthmaPatients.length, 1);
      expect(asthmaPatients.first.fullName, 'Priya Patel');
    });

    test('AudienceType.byGender filters accurately', () {
      final females = CampaignAudienceHelper.filterPatients(
        allPatients: samplePatients,
        audienceType: AudienceType.byGender,
        filters: {'gender': 'female'},
      );
      expect(females.length, 1);
      expect(females.first.firstName, 'Priya');

      final males = CampaignAudienceHelper.filterPatients(
        allPatients: samplePatients,
        audienceType: AudienceType.byGender,
        filters: {'gender': 'male'},
      );
      expect(males.length, 2); // Rahul, Aarav (Archived excluded)
    });

    test('AudienceType.byAgeGroup filters seniors and children accurately', () {
      final seniors = CampaignAudienceHelper.filterPatients(
        allPatients: samplePatients,
        audienceType: AudienceType.byAgeGroup,
        filters: {'minAge': 60, 'maxAge': 120},
      );
      expect(seniors.length, 1);
      expect(seniors.first.firstName, 'Rahul');

      final children = CampaignAudienceHelper.filterPatients(
        allPatients: samplePatients,
        audienceType: AudienceType.byAgeGroup,
        filters: {'minAge': 0, 'maxAge': 17},
      );
      expect(children.length, 1);
      expect(children.first.firstName, 'Aarav');
    });

    test('AudienceType.customSelection returns only selected IDs', () {
      final selected = CampaignAudienceHelper.filterPatients(
        allPatients: samplePatients,
        audienceType: AudienceType.customSelection,
        selectedPatientIds: ['p2', 'p4'],
      );
      expect(selected.length, 2);
      expect(selected.map((p) => p.id), containsAll(['p2', 'p4']));
    });

    test('Template variable interpolation replaces tokens accurately', () {
      const template =
          'Hello {{patient_name}}, please visit {{clinic_name}} for your consultation with {{doctor_name}}. Contact: {{phone}}';
      final interpolated = CampaignAudienceHelper.interpolateVariables(
        template,
        patient: samplePatients[0],
        clinicName: 'CruDoc Care Clinic',
        doctorName: 'Dr. Vinit Shah',
      );

      expect(interpolated, contains('Hello Rahul Sharma'));
      expect(interpolated, contains('CruDoc Care Clinic'));
      expect(interpolated, contains('Dr. Vinit Shah'));
      expect(interpolated, contains('+919876543210'));
      expect(interpolated, isNot(contains('{{')));
    });

    test('HTML Email builder generates valid responsive HTML with header & signature', () {
      final html = CampaignAudienceHelper.buildFormattedEmailHtml(
        'Special wellness camp for {{patient_name}}.\nFree BMI and sugar test included.',
        title: 'Community Health Camp',
        patient: samplePatients[0],
        category: CampaignCategory.checkupCamp,
        clinicName: 'CruDoc Clinic',
        doctorName: 'Dr. Vinit',
        mediaUrl: 'https://example.com/camp.jpg',
      );

      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('Community Health Camp'));
      expect(html, contains('Rahul Sharma'));
      expect(html, contains('CruDoc Clinic'));
      expect(html, contains('Dr. Vinit'));
      expect(html, contains('https://example.com/camp.jpg'));
      expect(html, contains('HEALTH CHECKUP CAMP'));
    });

    test('WhatsApp text builder constructs formatted markdown with emojis & footer', () {
      final waText = CampaignAudienceHelper.buildFormattedWhatsAppText(
        'Dear {{patient_name}}, we are hosting a wellness checkup.',
        title: 'Vaccine Drive',
        patient: samplePatients[1],
        category: CampaignCategory.vaccinationDrive,
        clinicName: 'Apollo Care',
        doctorName: 'Dr. Mehta',
      );

      expect(waText, startsWith('💉 *Vaccine Drive*'));
      expect(waText, contains('_Apollo Care_'));
      expect(waText, contains('Dear Priya Patel, we are hosting a wellness checkup.'));
      expect(waText, contains('👨‍⚕️ *Dr. Mehta*'));
      expect(waText, contains('🏥 Apollo Care'));
    });

    test('Email validator accurately validates RFC 5322 email patterns', () {
      expect(CampaignAudienceHelper.isValidEmail('doctor@crudoc.com'), isTrue);
      expect(CampaignAudienceHelper.isValidEmail('patient.name+tag@sub.domain.org'), isTrue);
      expect(CampaignAudienceHelper.isValidEmail(''), isFalse);
      expect(CampaignAudienceHelper.isValidEmail('invalid-email'), isFalse);
      expect(CampaignAudienceHelper.isValidEmail('missing@domain'), isFalse);
      expect(CampaignAudienceHelper.isValidEmail('@nodomain.com'), isFalse);
    });
  });

  group('Campaign Dispatch — honest delivery (no fabricated sends)', () {
    late _FakeCampaignRepository repo;

    setUp(() => repo = _FakeCampaignRepository());

    CampaignDispatchService buildService({required bool allowSimulation}) {
      return CampaignDispatchService(
        campaignRepository: repo,
        gmailAuthService: _FakeGmailAuthService(connected: false),
        gmailSendService: _FakeGmailSendService(),
        allowSimulation: allowSimulation,
      );
    }

    test('production build fails WhatsApp honestly instead of simulating', () async {
      final result = await buildService(allowSimulation: false).dispatchCampaign(
        campaign: _campaign(channels: CampaignChannel.whatsapp),
        targetPatients: [_patient(id: 'p1', phone: '+919876543210')],
      );

      expect(result.status, CampaignStatus.failed);
      expect(result.whatsAppSent, 0);
      expect(result.whatsAppFailed, 1);

      final log = repo.savedLogs.single;
      expect(log.whatsAppStatus, RecipientDeliveryStatus.failed);
      expect(log.whatsAppSimulated, isFalse);
      expect(log.whatsAppError, contains('not configured'));
    });

    test('debug build simulates WhatsApp but flags it, never claims delivered', () async {
      final result = await buildService(allowSimulation: true).dispatchCampaign(
        campaign: _campaign(channels: CampaignChannel.whatsapp),
        targetPatients: [_patient(id: 'p1', phone: '+919876543210')],
      );

      expect(result.status, CampaignStatus.completed);
      expect(result.whatsAppSent, 1);

      final log = repo.savedLogs.single;
      expect(log.whatsAppSimulated, isTrue);
      // A simulated send is never presented as a confirmed delivery.
      expect(log.whatsAppStatus, RecipientDeliveryStatus.sent);
    });

    test('production build fails email honestly when Gmail is not connected', () async {
      final result = await buildService(allowSimulation: false).dispatchCampaign(
        campaign: _campaign(channels: CampaignChannel.email),
        targetPatients: [_patient(id: 'p1', email: 'patient@example.com')],
      );

      expect(result.status, CampaignStatus.failed);
      expect(result.emailsSent, 0);
      expect(result.emailsFailed, 1);

      final log = repo.savedLogs.single;
      expect(log.emailStatus, RecipientDeliveryStatus.failed);
      expect(log.emailSimulated, isFalse);
      expect(log.emailError, contains('Gmail'));
    });

    test('debug build simulates email but flags it', () async {
      final result = await buildService(allowSimulation: true).dispatchCampaign(
        campaign: _campaign(channels: CampaignChannel.email),
        targetPatients: [_patient(id: 'p1', email: 'patient@example.com')],
      );

      expect(result.status, CampaignStatus.completed);
      expect(result.emailsSent, 1);

      final log = repo.savedLogs.single;
      expect(log.emailSimulated, isTrue);
      expect(log.emailStatus, RecipientDeliveryStatus.sent);
    });

    test('invalid contact details fail regardless of simulation setting', () async {
      final result = await buildService(allowSimulation: true).dispatchCampaign(
        campaign: _campaign(channels: CampaignChannel.email),
        targetPatients: [_patient(id: 'p1', email: '')],
      );

      expect(result.emailsFailed, 1);
      final log = repo.savedLogs.single;
      expect(log.emailStatus, RecipientDeliveryStatus.failed);
      expect(log.emailSimulated, isFalse);
    });
  });
}

CampaignModel _campaign({required CampaignChannel channels}) {
  final now = DateTime(2026, 10, 9, 9, 0);
  return CampaignModel(
    id: 'camp-test',
    doctorId: 'doc-test',
    title: 'Seasonal Advisory',
    message: 'Dear {{patient_name}}, stay hydrated this summer.',
    channels: channels,
    createdAt: now,
    updatedAt: now,
  );
}

Patient _patient({required String id, String phone = '', String email = ''}) {
  final now = DateTime(2026, 10, 9);
  return Patient(
    id: id,
    firstName: 'Test',
    lastName: 'Patient',
    phone: phone,
    email: email,
    gender: 'Female',
    dateOfBirth: DateTime(1990, 1, 1),
    diagnosis: const [],
    packageBalance: 0,
    isArchived: false,
    createdAt: now,
    updatedAt: now,
  );
}

/// In-memory stand-in for [CampaignRepository] that records writes without
/// touching Firestore. Only the methods the dispatcher uses are implemented;
/// anything else throws via [noSuchMethod].
class _FakeCampaignRepository implements CampaignRepository {
  final List<CampaignRecipientLog> savedLogs = [];
  CampaignModel? lastCampaign;

  @override
  Future<void> createCampaign(CampaignModel campaign) async {
    lastCampaign = campaign;
  }

  @override
  Future<void> updateCampaign(CampaignModel campaign) async {
    lastCampaign = campaign;
  }

  @override
  Future<void> saveRecipientLogsBatch(
    String doctorId,
    String campaignId,
    List<CampaignRecipientLog> logs,
  ) async {
    for (final log in logs) {
      _upsert(log);
    }
  }

  @override
  Future<void> saveRecipientLog(CampaignRecipientLog log) async => _upsert(log);

  @override
  Future<List<CampaignRecipientLog>> getRecipientLogs(
    String doctorId,
    String campaignId,
  ) async => List.of(savedLogs);

  @override
  Future<CampaignModel?> getCampaign(
    String doctorId,
    String campaignId,
  ) async => lastCampaign;

  void _upsert(CampaignRecipientLog log) {
    savedLogs.removeWhere((e) => e.id == log.id);
    savedLogs.add(log);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeGmailAuthService implements GmailAuthService {
  _FakeGmailAuthService({this.connected = false});
  final bool connected;

  @override
  bool get isConnected => connected;

  @override
  Future<bool> restoreSession() async => connected;

  @override
  String? get connectedEmail => connected ? 'doctor@example.com' : null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakeGmailSendService implements GmailSendService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
