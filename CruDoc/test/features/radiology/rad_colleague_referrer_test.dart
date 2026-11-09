import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_repository.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';

class _FakeRepo extends RadiologyRepository {
  _FakeRepo(this._saved);
  final List<RadReferrer> _saved;

  @override
  Future<List<RadReferrer>> referrers(String doctorId) async => _saved;
}

void main() {
  group('RadReferrer model', () {
    test('isColleague defaults to false for standard referrers', () {
      final r = RadReferrer(
        id: 'ref_123',
        name: 'Dr. John External',
        createdAt: DateTime(2026, 1, 1),
      );
      expect(r.isColleague, isFalse);
    });

    test('isColleague is true when id starts with colleague_', () {
      final r = RadReferrer.fromJson({
        'id': 'colleague_doc_abc',
        'name': 'Dr. Sarah Colleague',
        'createdAt': DateTime(2026, 1, 1).millisecondsSinceEpoch,
      });
      expect(r.isColleague, isTrue);
    });

    test('toJson and fromJson preserve isColleague and other fields', () {
      final r = RadReferrer(
        id: 'colleague_doc_xyz',
        name: 'Dr. Dave',
        clinic: 'Orthodontics',
        phone: '1234567890',
        email: 'dave@clinic.com',
        notes: 'Colleague · Doctor',
        createdAt: DateTime(2026, 2, 1),
        isColleague: true,
      );
      final json = r.toJson();
      expect(json['isColleague'], isTrue);

      final revived = RadReferrer.fromJson(json);
      expect(revived.id, 'colleague_doc_xyz');
      expect(revived.name, 'Dr. Dave');
      expect(revived.clinic, 'Orthodontics');
      expect(revived.phone, '1234567890');
      expect(revived.email, 'dave@clinic.com');
      expect(revived.isColleague, isTrue);
    });
  });

  group('radReferrersProvider and radReferrerByIdProvider', () {
    test('automatically adds clinic colleagues to referrers list with colleagues first', () async {
      const colleagueMember = ClinicMember(
        uid: 'colleague_uid_1',
        name: 'Amit Verma',
        phone: '9876543210',
        email: 'amit@clinic.com',
        kind: MemberKind.doctor,
        roleId: 'doctor',
        roleName: 'Associate Dentist',
        perms: {ClinicPermission.clinicalView},
        active: true,
        isOwner: false,
        specialty: 'Endodontics',
        qualification: 'BDS, MDS',
        registrationNo: 'A-12345',
      );

      final externalReferrer = RadReferrer(
        id: 'ext_ref_1',
        name: 'Dr. External Specialist',
        clinic: 'External Imaging',
        createdAt: DateTime(2026, 1, 1),
      );

      final container = ProviderContainer(
        overrides: [
          radDocsVersionProvider.overrideWith((ref) => Stream.value(0)),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          activeClinicProvider.overrideWith((ref) => Stream.value(null)),
          radiologyRepositoryProvider.overrideWithValue(
            _FakeRepo([externalReferrer]),
          ),
          clinicMembersProvider.overrideWith(
            (ref) => Stream.value([colleagueMember]),
          ),
          radDoctorIdProvider.overrideWithValue('test_clinic'),
        ],
      );
      addTearDown(container.dispose);

      // Keep radReferrersProvider subscribed so updates flow
      container.listen(radReferrersProvider, (previous, next) {});

      // Allow StreamProvider to emit its first value
      await container.read(clinicMembersProvider.future);
      await Future<void>.delayed(Duration.zero);

      final list = await container.read(radReferrersProvider.future);

      // Should have 2 referrers: colleague and external
      expect(list.length, 2);

      // Colleague should be sorted first
      expect(list.first.isColleague, isTrue);
      expect(list.first.id, 'colleague_colleague_uid_1');
      expect(list.first.name, 'Dr. Amit Verma');
      expect(list.first.clinic, 'Endodontics');
      expect(list.first.phone, '9876543210');
      expect(list.first.email, 'amit@clinic.com');
      expect(list.first.regNo, 'A-12345');

      // External referrer comes second
      expect(list.last.id, 'ext_ref_1');
      expect(list.last.isColleague, isFalse);

      // radReferrerByIdProvider maps both 'colleague_colleague_uid_1' and 'colleague_uid_1'
      final map = container.read(radReferrerByIdProvider);
      expect(map['colleague_colleague_uid_1']?.name, 'Dr. Amit Verma');
      expect(map['colleague_uid_1']?.name, 'Dr. Amit Verma');
      expect(map['ext_ref_1']?.name, 'Dr. External Specialist');
    });

    test('ignores inactive members', () async {
      const inactiveMember = ClinicMember(
        uid: 'inactive_uid',
        name: 'Old Doctor',
        phone: '',
        email: '',
        kind: MemberKind.doctor,
        roleId: 'doctor',
        roleName: 'Doctor',
        perms: {},
        active: false,
        isOwner: false,
        specialty: '',
        qualification: '',
        registrationNo: '',
      );

      final container = ProviderContainer(
        overrides: [
          radDocsVersionProvider.overrideWith((ref) => Stream.value(0)),
          authStateProvider.overrideWith((ref) => Stream.value(null)),
          activeClinicProvider.overrideWith((ref) => Stream.value(null)),
          radiologyRepositoryProvider.overrideWithValue(_FakeRepo([])),
          clinicMembersProvider.overrideWith(
            (ref) => Stream.value([inactiveMember]),
          ),
          radDoctorIdProvider.overrideWithValue('test_clinic'),
        ],
      );
      addTearDown(container.dispose);

      container.listen(radReferrersProvider, (previous, next) {});
      await container.read(clinicMembersProvider.future);
      await Future<void>.delayed(Duration.zero);

      final list = await container.read(radReferrersProvider.future);
      expect(list.isEmpty, isTrue);
    });
  });
}
