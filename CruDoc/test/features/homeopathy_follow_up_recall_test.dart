import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/dental/records/dental_records_repo.dart';
import 'package:doctor_management_app/features/dental/records/recalls.dart';
import 'package:doctor_management_app/features/homeopathy/data/homeopathy_follow_up_recall.dart';

/// A homeopathy follow-up date now raises a recall, which ends in a reminder
/// to a real patient. Two things decide whether that works: the shape of the
/// record (the recall list reads `reason`, the reminder drops it into its
/// sentence, the due-count filters on `status`), and which existing recalls a
/// re-save is allowed to replace.
void main() {
  DentalRecord recall({
    String source = kHomeoFollowUpSource,
    String status = 'pending',
  }) => DentalRecord.create('p1', RecKind.recall, {
    'patientName': 'Alice Smith',
    'reason': kHomeoFollowUpReason,
    'status': status,
    'source': source,
  }, at: DateTime(2026, 7, 1));

  group('isOursToReplace', () {
    test('an open recall this file wrote', () {
      expect(isOursToReplace(recall()), isTrue);
      expect(isOursToReplace(recall(status: 'sent')), isTrue);
      expect(isOursToReplace(recall(status: 'noResponse')), isTrue);
    });

    test('never a recall from somewhere else', () {
      expect(isOursToReplace(recall(source: 'procedure')), isFalse);
      expect(isOursToReplace(recall(source: 'package')), isFalse);
      expect(isOursToReplace(recall(source: '')), isFalse);
    });

    test('never one the doctor has already acted on', () {
      // Booked or called off: the reminder did its job, so moving the
      // follow-up date must not quietly delete the history of it.
      expect(isOursToReplace(recall(status: 'done')), isFalse);
      expect(isOursToReplace(recall(status: 'cancelled')), isFalse);
    });
  });

  group('homeoFollowUpRecallData', () {
    final data = homeoFollowUpRecallData(
      patientName: 'Alice Smith',
      notes: '  Sulphur 200  ',
    );

    test('starts open, so it counts as due', () {
      expect(data['status'], RecallStatus.pending.name);
      expect(RecallStatus.fromName(data['status'] as String).isOpen, isTrue);
    });

    test('is marked as ours, so a re-save replaces it', () {
      expect(data['source'], kHomeoFollowUpSource);
      expect(isOursToReplace(recall()), isTrue);
    });

    test('carries no rule, so the reminder uses the dated wording', () {
      expect(data['ruleId'], '');
    });

    test('the reason reads as part of the reminder sentence', () {
      final reason = (data['reason'] as String).toLowerCase();
      expect(
        'that your $reason is due on 1 July.',
        'that your homeopathy follow-up is due on 1 July.',
      );
    });

    test('the remedy rides along as the note, trimmed', () {
      expect(data['notes'], 'Sulphur 200');
    });

    test('no remedy is an empty note, never a placeholder', () {
      final bare = homeoFollowUpRecallData(patientName: 'Alice Smith');
      expect(bare['notes'], '');
    });
  });
}
