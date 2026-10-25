import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/providers/visit_providers.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:doctor_management_app/features/revenue/data/models/revenue_entry.dart';
import 'package:doctor_management_app/features/revenue/data/providers/revenue_providers.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/team/domain/team_stats.dart';
import 'package:doctor_management_app/features/team/presentation/team_analytics_view.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

import '../../patients/patients_fixtures.dart' show loadGeist;

ClinicMember _member(
  String uid,
  String name,
  String role, {
  bool owner = false,
  MemberKind kind = MemberKind.doctor,
}) => ClinicMember(
  uid: uid,
  name: name,
  phone: '',
  email: '',
  kind: kind,
  roleId: owner ? 'admin' : role.toLowerCase(),
  roleName: role,
  perms: ClinicPermission.values.toSet(),
  active: true,
  isOwner: owner,
  specialty: '',
  qualification: '',
  registrationNo: '',
);

void main() {
  setUpAll(loadGeist);

  testWidgets('Analytics tab shows the clinic and each person', (tester) async {
    final now = DateTime.now();
    DateTime ago(int days, [int hour = 10]) => DateTime(
      now.year,
      now.month,
      now.day,
      hour,
    ).subtract(Duration(days: days));
    Visit visit(int i, String by, String doc, VisitStatus s) => Visit(
      id: 'v$i',
      patientId: 'p$i',
      scheduledStart: ago(i % 20),
      durationMinutes: 15,
      address: '',
      status: s,
      createdAt: ago(i % 20 + 1),
      updatedAt: ago(i % 20),
      createdByUid: by,
      attendingDoctorUid: doc,
    );
    final visits = [
      for (var i = 0; i < 14; i++)
        visit(i, 'front', 'owner', VisitStatus.completed),
      for (var i = 14; i < 23; i++)
        visit(i, 'front', 'drb', VisitStatus.completed),
      for (var i = 23; i < 26; i++)
        visit(i, 'owner', 'drb', VisitStatus.scheduled),
      visit(26, '', '', VisitStatus.completed),
    ];
    final queue = [
      for (var i = 0; i < 6; i++)
        QueueEntry(
          id: 'q$i',
          tokenNumber: i + 1,
          queueDate: '',
          status: QueueStatus.completed,
          checkedInAt: ago(i, 9),
          createdAt: ago(i, 9),
          updatedAt: ago(i, 9),
          createdByUid: 'front',
        ),
    ];
    final revenue = [
      for (var i = 0; i < 8; i++)
        RevenueEntry(
          id: 'r$i',
          date: ago(i),
          description: '',
          amount: 750,
          type: RevenueType.visit,
          createdByUid: i.isEven ? 'front' : 'owner',
          createdAt: ago(i, 18),
          updatedAt: ago(i, 18),
        ),
    ];
    final logs = [
      for (var i = 0; i < 31; i++)
        TeamLogEntry(
          actorUid: i < 19 ? 'owner' : 'drb',
          action: i % 7 == 0 ? 'file.download' : 'patient.view',
          at: ago(i % 9, 11),
        ),
    ];

    tester.view.devicePixelRatio = 1.5;
    tester.view.physicalSize = const Size(900, 1400) * 1.5;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          clinicMembersProvider.overrideWith(
            (ref) => Stream.value([
              _member('owner', 'Dr. Asha Rao', 'Owner', owner: true),
              _member('drb', 'Dr. Vikram Shah', 'Doctor'),
              _member(
                'front',
                'Meera Pillai',
                'Front desk',
                kind: MemberKind.staff,
              ),
              _member('new', 'Rohan Das', 'Assistant', kind: MemberKind.staff),
            ]),
          ),
          allVisitsProvider.overrideWith((ref) => Stream.value(visits)),
          allQueueProvider.overrideWith((ref) => Stream.value(queue)),
          recentRevenueEntriesProvider.overrideWith(
            (ref) => Stream.value(revenue),
          ),
          teamInvoicesProvider.overrideWith((ref) => Stream.value(const [])),
          teamLogsProvider.overrideWith((ref, _) => Stream.value(logs)),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: CruTheme.day(),
          home: Scaffold(
            backgroundColor: CruColors.day.canvas,
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: Container(
                  color: CruColors.day.canvas,
                  padding: const EdgeInsets.all(24),
                  child: const TeamAnalyticsView(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dr. Asha Rao'), findsOneWidget);
    expect(find.text('Meera Pillai'), findsOneWidget);
    expect(find.textContaining('No activity in this period'), findsOneWidget);
    expect(find.textContaining('made before CruDoc noted'), findsOneWidget);

    final out = Platform.environment['TEAM_ANALYTICS_PNG'];
    if (out != null) {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(out).writeAsBytes(png!.buffer.asUint8List());
      });
    }
  });
}
