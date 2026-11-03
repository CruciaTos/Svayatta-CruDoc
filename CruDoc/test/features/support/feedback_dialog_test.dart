import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/core/clinic/clinic_access.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/support/data/support_ticket_service.dart';
import 'package:doctor_management_app/features/support/presentation/feedback_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Records what would be sent instead of writing to Firestore.
class _FakeService extends SupportTicketService {
  final sent = <({SupportTicketKind kind, String message, SupportTicketSender sender})>[];
  SupportTicketOutcome outcome = SupportTicketOutcome.sent;

  @override
  Future<SupportTicketOutcome> submit({
    required SupportTicketKind kind,
    required String message,
    SupportTicketSender sender = const SupportTicketSender(),
  }) async {
    sent.add((kind: kind, message: message, sender: sender));
    return outcome;
  }
}

Future<void> _pump(WidgetTester tester, _FakeService service) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        doctorIdentityProvider.overrideWithValue(
          const DoctorIdentity(
            fullName: 'Dr. Asha Patil',
            clinicName: 'Patil Clinic',
          ),
        ),
        clinicAccessProvider.overrideWith(
          (ref) => Stream.value(ClinicAccess.owner('doc-1')),
        ),
      ],
      child: MaterialApp(
        theme: CruTheme.day(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showFeedbackDialog(context, service: service),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('ticket document', () {
    test('uses the Super Admin Support screen field names', () {
      final t = SupportTicketService.buildTicket(
        uid: 'doc-1',
        kind: SupportTicketKind.bug,
        message: '  Swipe changes tab\nSteps: open Patients, swipe a row  ',
        email: 'asha@clinic.test',
        phone: '+919800000000',
        sender: const SupportTicketSender(
          name: 'Dr. Asha Patil',
          clinicId: 'doc-1',
          clinicName: 'Patil Clinic',
          role: 'Owner',
        ),
        platform: 'android',
        device: 'Android Mobile / Tablet',
        appVersion: '1.0.0+1',
      );
      expect(t['doctorId'], 'doc-1');
      expect(t['doctorName'], 'Dr. Asha Patil');
      expect(t['doctorEmail'], 'asha@clinic.test');
      expect(t['doctorPhone'], '+919800000000');
      expect(t['category'], 'bug');
      expect(t['subject'], 'Swipe changes tab');
      expect(
        t['description'],
        'Swipe changes tab\nSteps: open Patients, swipe a row',
      );
      expect(t['priority'], 'medium');
      expect(t['status'], 'open');
      expect(t['isArchived'], false);
      expect(t['createdAt'], isA<FieldValue>());
      expect(t['updatedAt'], isA<FieldValue>());
      expect(t['clinicId'], 'doc-1');
      expect(t['clinicName'], 'Patil Clinic');
      expect(t['role'], 'Owner');
      expect(t['platform'], 'android');
      expect(t['device'], 'Android Mobile / Tablet');
      expect(t['appVersion'], '1.0.0+1');
    });

    test('feedback is stored as feedback; no name falls back to email', () {
      final t = SupportTicketService.buildTicket(
        uid: 'u',
        kind: SupportTicketKind.feedback,
        message: 'Love it',
        email: 'x@clinic.test',
        sender: const SupportTicketSender(name: '  '),
        platform: 'windows',
        device: 'Windows Desktop App',
        appVersion: '1.0.0+1',
      );
      expect(t['category'], 'feedback');
      expect(t['doctorName'], 'x@clinic.test');
      expect(t['doctorPhone'], isNull);
    });

    test('a long first line becomes a short subject', () {
      final long = 'word ' * 40;
      final subject = SupportTicketService.subjectOf(long);
      expect(subject.length, lessThanOrEqualTo(81));
      expect(subject, endsWith('…'));
      expect(SupportTicketService.subjectOf('Short one'), 'Short one');
    });
  });

  testWidgets('sends a bug report with who sent it', (tester) async {
    final service = _FakeService();
    await _pump(tester, service);
    expect(find.text('Report a bug or send feedback'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'Swipe changes the tab');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(service.sent, hasLength(1));
    final s = service.sent.single;
    expect(s.kind, SupportTicketKind.bug);
    expect(s.message, 'Swipe changes the tab');
    expect(s.sender.name, 'Dr. Asha Patil');
    expect(s.sender.clinicName, 'Patil Clinic');
    expect(s.sender.clinicId, 'doc-1');
    expect(s.sender.role, 'Owner');
    // Closed, with a thank-you.
    expect(find.text('Report a bug or send feedback'), findsNothing);
    expect(find.text('Thank you. The CruDoc team has it.'), findsOneWidget);
  });

  testWidgets('sends feedback when that is chosen', (tester) async {
    final service = _FakeService();
    await _pump(tester, service);
    await tester.tap(find.text('Feedback'));
    await tester.pump();
    expect(find.text('Your feedback'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), 'Add dark mode');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(service.sent.single.kind, SupportTicketKind.feedback);
  });

  testWidgets('an empty message is not sent', (tester) async {
    final service = _FakeService();
    await _pump(tester, service);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(service.sent, isEmpty);
    expect(find.text('Tell us what went wrong.'), findsOneWidget);
  });

  testWidgets('offline: says it will go when back online', (tester) async {
    final service = _FakeService()..outcome = SupportTicketOutcome.queued;
    await _pump(tester, service);
    await tester.enterText(find.byType(EditableText), 'Crash on save');
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    expect(
      find.text("You're offline. It will be sent when you're back online."),
      findsOneWidget,
    );
  });
}
