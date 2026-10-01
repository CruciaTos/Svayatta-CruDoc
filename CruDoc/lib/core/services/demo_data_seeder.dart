import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/features/appointments/data/model/visits_model.dart';
import 'package:doctor_management_app/features/appointments/data/repo/visits_repo.dart';
import 'package:doctor_management_app/features/inventory/data/models/medicine_model.dart';
import 'package:doctor_management_app/features/inventory/data/repo/inventory_repository.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/repo/patient_repository.dart';
import 'package:doctor_management_app/features/queue/data/repo/queue_repository.dart';

/// Fills a demo account with randomised patients, visits, payments, queue
/// tokens and medicines so every screen can be seen with data in it.
///
/// Only ever called for demo logins, and only when the account has no
/// patients yet — a demo account that already has data is left alone.
/// Everything goes through the normal repositories, so it is stored and
/// synced exactly like data a doctor enters by hand.
class DemoDataSeeder {
  DemoDataSeeder._();

  static const _firstNames = [
    'Aarav', 'Ananya', 'Rohan', 'Priya', 'Kabir', 'Isha', 'Vihaan', 'Meera',
    'Arjun', 'Diya', 'Aditya', 'Sneha', 'Rahul', 'Kavya', 'Nikhil', 'Pooja',
    'Siddharth', 'Neha', 'Omkar', 'Tanvi',
  ];
  static const _lastNames = [
    'Sharma', 'Patil', 'Kulkarni', 'Deshmukh', 'Iyer', 'Mehta', 'Joshi',
    'Nair', 'Reddy', 'Gupta', 'Shinde', 'Rao', 'Kapoor', 'Pawar',
  ];
  static const _diagnoses = [
    'Hypertension', 'Type 2 diabetes', 'Migraine', 'Asthma', 'Back pain',
    'Dental caries', 'Gingivitis', 'Anxiety', 'Hypothyroidism', 'Eczema',
    'Knee osteoarthritis', 'Acid reflux', 'Allergic rhinitis',
  ];
  static const _reasons = [
    'Follow-up', 'Fever and cough', 'Routine check-up', 'Tooth pain',
    'Report review', 'Dressing change',
  ];
  static const _medicines = [
    ('Paracetamol 500 mg', 'Analgesic', 'tablet'),
    ('Amoxicillin 500 mg', 'Antibiotic', 'capsule'),
    ('Cetirizine 10 mg', 'Antihistamine', 'tablet'),
    ('Pantoprazole 40 mg', 'Antacid', 'tablet'),
    ('Ibuprofen 400 mg', 'Analgesic', 'tablet'),
    ('Chlorhexidine mouthwash', 'Antiseptic', 'bottle'),
    ('Vitamin D3 60K', 'Supplement', 'capsule'),
    ('Lidocaine 2%', 'Anaesthetic', 'vial'),
  ];

  /// Seeds the signed-in account if it has no patients. Never throws:
  /// a failed seed only means the demo opens emptier than intended.
  static Future<void> seedIfEmpty() async {
    try {
      final patients = PatientRepository();
      if ((await patients.getAllPatients()).isNotEmpty) return;
      await _seed(patients);
    } catch (e) {
      debugPrint('Demo data seed failed: $e');
    }
  }

  static Future<void> _seed(PatientRepository patientRepo) async {
    final rnd = Random();
    final visits = VisitRepository();
    final queue = QueueRepository();
    final inventory = InventoryRepository();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    T pick<T>(List<T> list) => list[rnd.nextInt(list.length)];

    final patientIds = <String>[];
    final usedNames = <String>{};
    while (patientIds.length < 14) {
      final first = pick(_firstNames);
      final last = pick(_lastNames);
      if (!usedNames.add('$first $last')) continue;
      final created = now.subtract(Duration(days: 10 + rnd.nextInt(170)));
      patientIds.add(
        await patientRepo.createPatient(
          Patient(
            id: '',
            firstName: first,
            lastName: last,
            phone: '9${(100000000 + rnd.nextInt(899999999))}',
            email: '${first.toLowerCase()}.${last.toLowerCase()}@example.com',
            gender: _femaleNames.contains(first) ? 'Female' : 'Male',
            dateOfBirth: DateTime(
              now.year - 8 - rnd.nextInt(62),
              1 + rnd.nextInt(12),
              1 + rnd.nextInt(28),
            ),
            diagnosis: {pick(_diagnoses), if (rnd.nextBool()) pick(_diagnoses)}
                .toList(),
            notes: '',
            packageBalance: 0,
            isArchived: false,
            createdAt: created,
            updatedAt: created,
          ),
        ),
      );
    }

    Future<String> visit(
      String patientId,
      DateTime start,
      VisitStatus status, {
      VisitType type = VisitType.clinic,
    }) {
      return visits.createVisit(
        Visit(
          id: '',
          patientId: patientId,
          scheduledStart: start,
          durationMinutes: pick(const [15, 20, 30, 45]),
          address: type == VisitType.home ? 'Shivaji Nagar, Pune' : '',
          status: status,
          visitType: type,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    // Past two weeks: mostly completed and paid, a few missed or unpaid.
    for (var day = 14; day >= 1; day--) {
      final date = today.subtract(Duration(days: day));
      if (date.weekday == DateTime.sunday) continue;
      for (var i = 0; i < 2 + rnd.nextInt(3); i++) {
        final start = date.add(Duration(hours: 9 + rnd.nextInt(9)));
        final roll = rnd.nextInt(10);
        final status = roll == 0 ? VisitStatus.missed : VisitStatus.completed;
        final id = await visit(pick(patientIds), start, status);
        if (status == VisitStatus.completed && roll > 2) {
          await visits.recordPayment(
            id,
            amount: pick(const [300.0, 500.0, 800.0, 1200.0, 1500.0]),
          );
        }
      }
    }

    // Today: the morning is done, the rest of the day is booked.
    for (final hour in const [9, 10, 11, 13, 15, 16, 17, 18]) {
      final start = today.add(Duration(hours: hour, minutes: pick(const [0, 30])));
      final done = start.isBefore(now);
      final id = await visit(
        pick(patientIds),
        start,
        done ? VisitStatus.completed : VisitStatus.scheduled,
        type: hour == 17 ? VisitType.home : VisitType.clinic,
      );
      if (done) {
        await visits.recordPayment(id, amount: pick(const [500.0, 800.0]));
      }
    }

    // Next week.
    for (var day = 1; day <= 7; day++) {
      final date = today.add(Duration(days: day));
      if (date.weekday == DateTime.sunday) continue;
      for (var i = 0; i < 1 + rnd.nextInt(3); i++) {
        await visit(
          pick(patientIds),
          date.add(Duration(hours: 9 + rnd.nextInt(9))),
          VisitStatus.scheduled,
        );
      }
    }

    // Today's queue: one in consultation, a few waiting, one walk-in.
    final first = await queue.checkIn(
      patientId: patientIds[0],
      reason: pick(_reasons),
    );
    await queue.startConsultation(first.id);
    for (final id in patientIds.sublist(1, 4)) {
      await queue.checkIn(patientId: id, reason: pick(_reasons));
    }
    await queue.checkIn(
      walkInName: '${pick(_firstNames)} ${pick(_lastNames)}',
      reason: pick(_reasons),
    );

    // Pharmacy stock, with a couple of items running low.
    for (var i = 0; i < _medicines.length; i++) {
      final (name, category, unit) = _medicines[i];
      await inventory.createMedicine(
        MedicineModel(
          id: '',
          name: name,
          category: category,
          unit: unit,
          currentStock: i.isEven ? 40 + rnd.nextInt(160) : rnd.nextInt(9),
          reorderThreshold: 10,
          unitPrice: (5 + rnd.nextInt(95)).toDouble(),
          expiryDate: now.add(Duration(days: 30 + rnd.nextInt(600))),
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  }

  static const _femaleNames = {
    'Ananya', 'Priya', 'Isha', 'Meera', 'Diya', 'Sneha', 'Kavya', 'Pooja',
    'Neha', 'Tanvi',
  };
}
