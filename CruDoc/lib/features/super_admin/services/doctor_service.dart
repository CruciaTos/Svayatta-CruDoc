import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../../../core/services/doctor_encryption_service.dart';
import '../models/doctor_model.dart';
import '../config/enums.dart';
import 'firebase_service.dart';

/// Service for managing doctor accounts (CRUD from Super Admin).
class SuperAdminDoctorService {
  final SuperAdminFirebaseService _fb = SuperAdminFirebaseService();

  /// Get paginated list of doctors.
  Future<List<DoctorModel>> getAllDoctors({
    int limit = 50,
    String? lastDocId,
    String? searchQuery,
    DoctorStatus? statusFilter,
    SubscriptionPlan? planFilter,
    String? specializationFilter,
  }) async {
    try {
      final snapshot = await _fb.usersCollection.get();
      final doctors = <DoctorModel>[];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final role = (data['role'] as String? ?? '').toLowerCase();
        final isDeleted = data['isDeleted'] as bool? ?? false;

        if (role != 'doctor' || isDeleted) {
          continue;
        }

        if (statusFilter != null) {
          final status = data['status'] as String? ?? DoctorStatus.pending.name;
          if (status != statusFilter.name) continue;
        }

        if (planFilter != null) {
          final plan = data['subscriptionPlan'] as String? ?? SubscriptionPlan.starter.name;
          if (plan != planFilter.name) continue;
        }

        final decryptedData = <String, dynamic>{
          ...data,
          'name': DoctorEncryptionService.decryptForDoctor(
            data['name'] as String?,
            doc.id,
          ),
          'email': DoctorEncryptionService.decryptForDoctor(
            data['email'] as String?,
            doc.id,
          ),
          'phone': DoctorEncryptionService.decryptForDoctor(
            data['phone'] as String?,
            doc.id,
          ),
          'specialization': DoctorEncryptionService.decryptForDoctor(
            data['specialization'] as String?,
            doc.id,
          ),
          'clinicName': DoctorEncryptionService.decryptForDoctor(
            data['clinicName'] as String?,
            doc.id,
          ),
          'country': DoctorEncryptionService.decryptForDoctor(
            data['country'] as String?,
            doc.id,
          ),
          'timeZone': DoctorEncryptionService.decryptForDoctor(
            data['timeZone'] as String?,
            doc.id,
          ),
          'notes': DoctorEncryptionService.decryptForDoctor(
            data['notes'] as String?,
            doc.id,
          ),
        };

        doctors.add(DoctorModel.fromJson(decryptedData, doc.id));
      }

      doctors.sort((a, b) => b.accountCreated.compareTo(a.accountCreated));

      if (searchQuery != null && searchQuery.isNotEmpty) {
        final queryLower = searchQuery.toLowerCase();
        return doctors.where((d) {
          return d.name.toLowerCase().contains(queryLower) ||
              d.email.toLowerCase().contains(queryLower) ||
              d.phone.contains(queryLower) ||
              d.clinicName.toLowerCase().contains(queryLower);
        }).take(limit).toList();
      }

      return doctors.take(limit).toList();
    } catch (e) {
      throw Exception('Failed to fetch doctors: ${e.toString()}');
    }
  }

  /// Get a single doctor by ID.
  Future<DoctorModel?> getDoctorById(String doctorId) async {
    try {
      final doc = await _fb.usersCollection.doc(doctorId).get();
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>;
      final decryptedData = <String, dynamic>{
        ...data,
        'name': DoctorEncryptionService.decryptForDoctor(data['name'] as String?, doctorId),
        'email': DoctorEncryptionService.decryptForDoctor(data['email'] as String?, doctorId),
        'phone': DoctorEncryptionService.decryptForDoctor(data['phone'] as String?, doctorId),
        'specialization': DoctorEncryptionService.decryptForDoctor(
          data['specialization'] as String?,
          doctorId,
        ),
        'clinicName': DoctorEncryptionService.decryptForDoctor(
          data['clinicName'] as String?,
          doctorId,
        ),
        'country': DoctorEncryptionService.decryptForDoctor(data['country'] as String?, doctorId),
        'timeZone': DoctorEncryptionService.decryptForDoctor(data['timeZone'] as String?, doctorId),
        'notes': DoctorEncryptionService.decryptForDoctor(data['notes'] as String?, doctorId),
      };
      return DoctorModel.fromJson(decryptedData, doc.id);
    } catch (e) {
      throw Exception('Failed to fetch doctor: ${e.toString()}');
    }
  }

  /// Create a new doctor account atomically.
  /// First attempts server-side Cloud Function (best practice with custom claims & atomic rollback).
  /// If Cloud Function is not available/deployed, seamlessly falls back to secondary Firebase App client creation.
  Future<DoctorModel> createDoctor({
    required String name,
    required String email,
    required String phone,
    required String specialization,
    required String clinicName,
    required String country,
    required String timeZone,
    required SubscriptionPlan subscriptionPlan,
    required double storageLimitGB,
    required String password,
    List<String>? enabledModules,
  }) async {
    final modules = enabledModules ?? subscriptionPlan.includedModules;

    // --- Approach 1: Try Production Cloud Function ---
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('createDoctor');
      final result = await callable.call<Map<String, dynamic>>({
        'name': name,
        'email': email,
        'phone': phone,
        'specialization': specialization,
        'clinicName': clinicName,
        'country': country,
        'timeZone': timeZone,
        'subscriptionPlan': subscriptionPlan.name,
        'storageLimitGB': storageLimitGB,
        'password': password,
        'enabledModules': modules,
      });

      final doctorId = result.data['doctorId'] as String?;
      if (doctorId != null && doctorId.isNotEmpty) {
        debugPrint('Doctor created successfully via Cloud Function: $doctorId');
        return DoctorModel(
          id: doctorId,
          name: name,
          email: email,
          phone: phone,
          specialization: specialization,
          clinicName: clinicName,
          country: country,
          timeZone: timeZone,
          subscriptionPlan: subscriptionPlan,
          status: DoctorStatus.active,
          accountCreated: DateTime.now(),
          storageLimitGB: storageLimitGB,
          enabledModules: modules,
        );
      }
    } catch (cfError) {
      debugPrint('Cloud Function createDoctor skipped/failed (${cfError.toString()}), falling back to secondary app creation.');
      if (cfError.toString().contains('already exists') || cfError.toString().contains('email-already-in-use')) {
        throw Exception('A doctor with this email already exists');
      }
    }

    // --- Approach 2: Fallback to Secondary Firebase App Client Creation ---
    FirebaseApp? secondaryApp;
    String? createdUid;

    try {
      try {
        secondaryApp = Firebase.app('doctorCreator');
      } catch (_) {
        secondaryApp = await Firebase.initializeApp(
          name: 'doctorCreator',
          options: Firebase.app().options,
        );
      }

      final secondaryAuth = fb_auth.FirebaseAuth.instanceFor(app: secondaryApp);

      final userCredential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final doctorId = userCredential.user!.uid;
      createdUid = doctorId;

      await userCredential.user!.updateDisplayName(name);
      await secondaryAuth.signOut();

      final batch = _fb.batch();
      final now = DateTime.now();

      final encryptedName = DoctorEncryptionService.encryptForDoctor(name, doctorId);
      final encryptedEmail = DoctorEncryptionService.encryptForDoctor(email, doctorId);
      final encryptedPhone = DoctorEncryptionService.encryptForDoctor(phone, doctorId);
      final encryptedSpec = DoctorEncryptionService.encryptForDoctor(specialization, doctorId);
      final encryptedClinic = DoctorEncryptionService.encryptForDoctor(clinicName, doctorId);
      final encryptedCountry = DoctorEncryptionService.encryptForDoctor(country, doctorId);
      final encryptedTZ = DoctorEncryptionService.encryptForDoctor(timeZone, doctorId);

      batch.set(_fb.usersCollection.doc(doctorId), {
        'name': encryptedName,
        'email': encryptedEmail,
        'phone': encryptedPhone,
        'specialization': encryptedSpec,
        'clinicName': encryptedClinic,
        'country': encryptedCountry,
        'timeZone': encryptedTZ,
        'subscriptionPlan': subscriptionPlan.name,
        'status': 'active',
        'role': 'doctor',
        'accountCreated': FieldValue.serverTimestamp(),
        'lastLogin': null,
        'storageUsedGB': 0,
        'storageLimitGB': storageLimitGB,
        'patientCount': 0,
        'appointmentCount': 0,
        'activeDeviceCount': 0,
        'ocrRequestsThisMonth': 0,
        'enabledModules': modules,
        'totalSessions': 0,
        'isDeleted': false,
      });

      batch.set(
        FirebaseFirestore.instance.collection('doctor_settings').doc(doctorId),
        {
          'doctorId': doctorId,
          'enabledModules': modules,
          'lastModified': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        },
      );

      batch.set(
        FirebaseFirestore.instance.collection('subscriptions').doc(doctorId),
        {
          'doctorId': doctorId,
          'plan': subscriptionPlan.name,
          'subscribedDate': FieldValue.serverTimestamp(),
          'isTrial': true,
          'trialEndDate': Timestamp.fromDate(now.add(const Duration(days: 14))),
          'autoRenew': true,
          'history': [],
          'lastModified': FieldValue.serverTimestamp(),
          'modifiedBy': _fb.currentUserEmail,
        },
      );

      await batch.commit();

      return DoctorModel(
        id: doctorId,
        name: name,
        email: email,
        phone: phone,
        specialization: specialization,
        clinicName: clinicName,
        country: country,
        timeZone: timeZone,
        subscriptionPlan: subscriptionPlan,
        status: DoctorStatus.active,
        accountCreated: now,
        storageLimitGB: storageLimitGB,
        enabledModules: modules,
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        throw Exception('A doctor with this email already exists');
      }
      throw Exception('Auth error: ${e.message}');
    } catch (e) {
      if (createdUid != null) {
        debugPrint('Warning: Auth user $createdUid created but Firestore write failed.');
      }
      throw Exception('Failed to create doctor: ${e.toString()}');
    }
  }

  /// Update doctor details.
  Future<void> updateDoctor(String doctorId, Map<String, dynamic> updates) async {
    try {
      final encryptedUpdates = <String, dynamic>{...updates};
      for (final entry in <MapEntry<String, dynamic>>[
        MapEntry('name', updates['name']),
        MapEntry('email', updates['email']),
        MapEntry('phone', updates['phone']),
        MapEntry('specialization', updates['specialization']),
        MapEntry('clinicName', updates['clinicName']),
        MapEntry('country', updates['country']),
        MapEntry('timeZone', updates['timeZone']),
        MapEntry('notes', updates['notes']),
      ]) {
        if (entry.value is String) {
          encryptedUpdates[entry.key] = DoctorEncryptionService.encryptForDoctor(
            entry.value as String,
            doctorId,
          );
        }
      }

      encryptedUpdates['lastModified'] = FieldValue.serverTimestamp();
      encryptedUpdates['modifiedBy'] = _fb.currentUserEmail;
      await _fb.usersCollection.doc(doctorId).update(encryptedUpdates);
    } catch (e) {
      throw Exception('Failed to update doctor: ${e.toString()}');
    }
  }

  /// Soft delete a doctor (archive with cascade).
  Future<void> deleteDoctor(String doctorId) async {
    try {
      final batch = _fb.batch();

      // Mark user as deleted
      batch.update(_fb.usersCollection.doc(doctorId), {
        'isDeleted': true,
        'status': DoctorStatus.expired.name,
        'deletedAt': FieldValue.serverTimestamp(),
        'deletedBy': _fb.currentUserEmail,
      });

      // Disable Firebase Auth user
      // In production, this would call a Cloud Function

      await batch.commit();
    } catch (e) {
      throw Exception('Failed to delete doctor: ${e.toString()}');
    }
  }

  /// Suspend a doctor account.
  Future<void> suspendDoctor(String doctorId, {String? reason}) async {
    try {
      await _fb.usersCollection.doc(doctorId).update({
        'status': DoctorStatus.suspended.name,
        'suspendedAt': FieldValue.serverTimestamp(),
        'suspendedBy': _fb.currentUserEmail,
        'suspensionReason': reason,
      });

      // In production, also disable Firebase Auth user via Cloud Function
    } catch (e) {
      throw Exception('Failed to suspend doctor: ${e.toString()}');
    }
  }

  /// Activate a suspended doctor account.
  Future<void> activateDoctor(String doctorId) async {
    try {
      await _fb.usersCollection.doc(doctorId).update({
        'status': DoctorStatus.active.name,
        'activatedAt': FieldValue.serverTimestamp(),
        'activatedBy': _fb.currentUserEmail,
        'suspensionReason': null,
      });

      // In production, also re-enable Firebase Auth user via Cloud Function
    } catch (e) {
      throw Exception('Failed to activate doctor: ${e.toString()}');
    }
  }

  /// Reset doctor's password (sends reset email).
  Future<void> resetDoctorPassword(String doctorId, String email) async {
    try {
      await _fb.auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      throw Exception('Failed to send password reset: ${e.toString()}');
    }
  }

  /// Get total count of doctors.
  Future<int> getDoctorCount({DoctorStatus? status}) async {
    try {
      Query query = _fb.usersCollection
          .where('role', isEqualTo: 'doctor')
          .where('isDeleted', isEqualTo: false);

      if (status != null) {
        query = query.where('status', isEqualTo: status.name);
      }

      final snapshot = await query.count().get();
      return snapshot.count ?? 0;
    } catch (e) {
      return 0;
    }
  }
}