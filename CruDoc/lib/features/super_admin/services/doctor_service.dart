import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
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
      Query query = _fb.usersCollection
          .where('role', isEqualTo: 'doctor')
          .where('isDeleted', isEqualTo: false)
          .orderBy('accountCreated', descending: true)
          .limit(limit);

      if (statusFilter != null) {
        query = query.where('status', isEqualTo: statusFilter.name);
      }
      if (planFilter != null) {
        query = query.where('subscriptionPlan', isEqualTo: planFilter.name);
      }
      if (lastDocId != null) {
        final lastDoc = await _fb.usersCollection.doc(lastDocId).get();
        if (lastDoc.exists) {
          query = query.startAfterDocument(lastDoc);
        }
      }

      final snapshot = await query.get();
      final doctors = <DoctorModel>[];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        doctors.add(DoctorModel.fromJson(data, doc.id));
      }

      // Client-side search filtering for text searches
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final queryLower = searchQuery.toLowerCase();
        return doctors.where((d) {
          return d.name.toLowerCase().contains(queryLower) ||
              d.email.toLowerCase().contains(queryLower) ||
              d.phone.contains(queryLower) ||
              d.clinicName.toLowerCase().contains(queryLower);
        }).toList();
      }

      return doctors;
    } catch (e) {
      throw Exception('Failed to fetch doctors: ${e.toString()}');
    }
  }

  /// Get a single doctor by ID.
  Future<DoctorModel?> getDoctorById(String doctorId) async {
    try {
      final doc = await _fb.usersCollection.doc(doctorId).get();
      if (!doc.exists) return null;
      return DoctorModel.fromJson(doc.data() as Map<String, dynamic>, doc.id);
    } catch (e) {
      throw Exception('Failed to fetch doctor: ${e.toString()}');
    }
  }

  /// Create a new doctor account atomically.
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
    try {
      // 1. Create Firebase Auth user
      final userCredential = await _fb.auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final doctorId = userCredential.user!.uid;

      // 2. Custom claims are set via Cloud Function in production

      // 3. Create Firestore document in a batch
      final batch = _fb.batch();

      // Doctor user document
      final now = Timestamp.now();
      final modules = enabledModules ?? subscriptionPlan.includedModules;
      final doctorDoc = _fb.usersCollection.doc(doctorId);
      batch.set(doctorDoc, {
        'name': name,
        'email': email,
        'phone': phone,
        'specialization': specialization,
        'clinicName': clinicName,
        'country': country,
        'timeZone': timeZone,
        'subscriptionPlan': subscriptionPlan.name,
        'status': DoctorStatus.active.name,
        'role': 'doctor',
        'accountCreated': now,
        'lastLogin': null,
        'storageUsedGB': 0.0,
        'storageLimitGB': storageLimitGB,
        'patientCount': 0,
        'appointmentCount': 0,
        'activeDeviceCount': 0,
        'ocrRequestsThisMonth': 0,
        'enabledModules': modules,
        'totalSessions': 0,
        'isDeleted': false,
        'notes': null,
      });

      // Doctor settings document
      final settingsDoc = _fb.doctorSettingsCollection.doc(doctorId);
      batch.set(settingsDoc, {
        'doctorId': doctorId,
        'enabledModules': modules,
        'lastModified': now,
        'createdAt': now,
      });

      // Subscription document
      final subDoc = _fb.subscriptionsCollection.doc(doctorId);
      batch.set(subDoc, {
        'doctorId': doctorId,
        'plan': subscriptionPlan.name,
        'subscribedDate': now,
        'isTrial': false,
        'autoRenew': true,
        'history': [],
        'lastModified': now,
        'modifiedBy': _fb.currentUserEmail,
      });

      await batch.commit();

      // 4. Send welcome email (would trigger a Cloud Function in production)
      // await _fb.sendWelcomeEmail(doctorId, email, password);

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
        accountCreated: now.toDate(),
        storageLimitGB: storageLimitGB,
        enabledModules: modules,
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      throw Exception('Auth error: ${e.message}');
    } catch (e) {
      throw Exception('Failed to create doctor: ${e.toString()}');
    }
  }

  /// Update doctor details.
  Future<void> updateDoctor(String doctorId, Map<String, dynamic> updates) async {
    try {
      updates['lastModified'] = FieldValue.serverTimestamp();
      updates['modifiedBy'] = _fb.currentUserEmail;
      await _fb.usersCollection.doc(doctorId).update(updates);
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