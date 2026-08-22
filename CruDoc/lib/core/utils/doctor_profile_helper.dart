import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:doctor_management_app/core/services/doctor_encryption_service.dart';
import 'package:doctor_management_app/core/services/field_cipher.dart';

/// Helper utility for streaming, formatting, and updating logged-in doctor profile information.
class DoctorProfileHelper {
  /// Stream of current doctor's profile document from Firestore `users/{uid}`
  static Stream<Map<String, dynamic>?> watchDoctorProfile([User? user]) async* {
    final currentUser = user ?? FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      yield null;
      return;
    }

    final uidDocRef =
        FirebaseFirestore.instance.collection('users').doc(currentUser.uid);
    await for (final snap in uidDocRef.snapshots()) {
      if (snap.exists && snap.data() != null) {
        yield snap.data();
      } else {
        // Fallback query by email if document ID isn't UID
        final email = currentUser.email?.trim();
        if (email != null && email.isNotEmpty) {
          final q1 = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: email.toLowerCase())
              .get();
          if (q1.docs.isNotEmpty) {
            yield q1.docs.first.data();
            continue;
          }
        }
        yield null;
      }
    }
  }

  /// Formats the doctor's full name dynamically from Firestore, Auth, or Email Handle.
  static String formatDoctorName(User? user, Map<String, dynamic>? data) {
    if (data != null) {
      final rawName = (data['displayName'] ??
          data['doctorName'] ??
          data['fullName'] ??
          data['name']) as String?;

      if (rawName != null && rawName.trim().isNotEmpty) {
        String cleanName = rawName;
        if (user != null) {
          cleanName =
              DoctorEncryptionService.decryptForDoctor(cleanName, user.uid);
        }
        cleanName = FieldCipher.decrypt(cleanName);

        final trimmed = cleanName.trim();
        if (trimmed.isNotEmpty && trimmed.toLowerCase() != 'doctor') {
          return trimmed.toLowerCase().startsWith('dr')
              ? trimmed
              : 'Dr. $trimmed';
        }
      }

      final firstName =
          (data['firstName'] ?? data['first_name'] ?? data['givenName'])
              as String?;
      final lastName =
          (data['lastName'] ?? data['last_name'] ?? data['familyName'])
              as String?;
      if (firstName != null && firstName.trim().isNotEmpty) {
        final combined = ((lastName != null && lastName.trim().isNotEmpty)
                ? '${firstName.trim()} ${lastName.trim()}'
                : firstName.trim())
            .trim();
        if (combined.toLowerCase() != 'doctor') {
          return combined.toLowerCase().startsWith('dr')
              ? combined
              : 'Dr. $combined';
        }
      }
    }

    if (user?.displayName != null &&
        user!.displayName!.trim().isNotEmpty &&
        user.displayName!.trim().toLowerCase() != 'doctor') {
      final name = user.displayName!.trim();
      return name.toLowerCase().startsWith('dr') ? name : 'Dr. $name';
    }

    if (user?.email != null && user!.email!.trim().isNotEmpty) {
      final rawName = user.email!.split('@').first;
      final cleanHandle = rawName.replaceAll(RegExp(r'\d+$'), '');
      final parts =
          cleanHandle.split(RegExp(r'[._-]')).where((p) => p.isNotEmpty);
      if (parts.isNotEmpty) {
        final formatted = parts
            .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
            .join(' ');
        if (formatted.toLowerCase() != 'doctor') {
          return 'Dr. $formatted';
        }
      }
    }

    return 'Dr. Vinit Parab';
  }

  /// Formats doctor's medical specialty / designation.
  static String formatSpecialty(Map<String, dynamic>? data, [User? user]) {
    if (data != null) {
      final rawSpec = (data['specialty'] ??
          data['specialization'] ??
          data['degree'] ??
          data['qualification']) as String?;
      if (rawSpec != null && rawSpec.trim().isNotEmpty) {
        String cleanSpec = rawSpec;
        if (user != null) {
          cleanSpec =
              DoctorEncryptionService.decryptForDoctor(cleanSpec, user.uid);
        }
        cleanSpec = FieldCipher.decrypt(cleanSpec);
        if (cleanSpec.trim().isNotEmpty) {
          return cleanSpec.trim();
        }
      }
    }
    return 'General Physician';
  }

  /// Formats the doctor's clinic / practice name from Firestore or default.
  static String formatClinicName(User? user, Map<String, dynamic>? data) {
    if (data != null) {
      final rawClinic = (data['clinicName'] ??
          data['practiceName'] ??
          data['clinic_name']) as String?;
      if (rawClinic != null && rawClinic.trim().isNotEmpty) {
        return rawClinic.trim();
      }
    }
    return 'CruDoc Healthcare';
  }

  /// Updates the logged-in doctor's profile name and specialty in Cloud Firestore and Auth.
  static Future<void> updateProfile({
    required String doctorName,
    required String specialty,
    User? user,
  }) async {
    final currentUser = user ?? FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final trimmedName = doctorName.trim();
    final trimmedSpecialty = specialty.trim();

    final encryptedName = DoctorEncryptionService.encryptForDoctor(
        trimmedName, currentUser.uid);
    final encryptedSpec = DoctorEncryptionService.encryptForDoctor(
        trimmedSpecialty, currentUser.uid);

    final docRef =
        FirebaseFirestore.instance.collection('users').doc(currentUser.uid);

    await docRef.set({
      'displayName': trimmedName,
      'doctorName': trimmedName,
      'name': encryptedName,
      'specialty': trimmedSpecialty,
      'specialization': encryptedSpec,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    try {
      await currentUser.updateDisplayName(trimmedName);
    } catch (_) {}
  }

  /// Updates the doctor's Letterhead & Branding settings for Bill and Prescription generation.
  static Future<void> updateLetterheadBranding({
    required String clinicName,
    required String doctorQualifications,
    required String registrationNumber,
    required String clinicAddress,
    required String clinicPhone,
    required String clinicEmail,
    required String tagline,
    required String footerDisclaimer,
    String? logoUrl,
    User? user,
  }) async {
    final currentUser = user ?? FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final docRef =
        FirebaseFirestore.instance.collection('users').doc(currentUser.uid);

    final payload = <String, dynamic>{
      'clinicName': clinicName.trim(),
      'practiceName': clinicName.trim(),
      'qualifications': doctorQualifications.trim(),
      'doctorQualifications': doctorQualifications.trim(),
      'registrationNumber': registrationNumber.trim(),
      'doctorRegistrationNumber': registrationNumber.trim(),
      'clinicAddress': clinicAddress.trim(),
      'clinicPhone': clinicPhone.trim(),
      'clinicEmail': clinicEmail.trim(),
      'letterheadTagline': tagline.trim(),
      'letterheadFooterDisclaimer': footerDisclaimer.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (logoUrl != null) {
      payload['clinicLogoUrl'] = logoUrl.trim();
    }

    await docRef.set(payload, SetOptions(merge: true));
  }
}

/// Structured container for Letterhead & Branding configurations used in Bills and Prescriptions.
class DoctorLetterheadConfig {
  const DoctorLetterheadConfig({
    required this.clinicName,
    required this.doctorName,
    required this.qualifications,
    required this.registrationNumber,
    required this.specialty,
    required this.clinicAddress,
    required this.clinicPhone,
    required this.clinicEmail,
    required this.tagline,
    required this.footerDisclaimer,
    this.logoUrl,
  });

  final String clinicName;
  final String doctorName;
  final String qualifications;
  final String registrationNumber;
  final String specialty;
  final String clinicAddress;
  final String clinicPhone;
  final String clinicEmail;
  final String tagline;
  final String footerDisclaimer;
  final String? logoUrl;

  factory DoctorLetterheadConfig.fromProfileData(
    Map<String, dynamic>? data,
    User? user,
  ) {
    final doctorName = DoctorProfileHelper.formatDoctorName(user, data);
    final specialty = DoctorProfileHelper.formatSpecialty(data, user);

    final clinicName = (data?['clinicName'] ?? data?['practiceName'] ?? 'CruDoc Multi-Speciality Clinic') as String;
    final qualifications = (data?['qualifications'] ?? data?['doctorQualifications'] ?? 'MBBS, MD (Medicine)') as String;
    final regNo = (data?['registrationNumber'] ?? data?['doctorRegistrationNumber'] ?? 'MMC-2024/98765') as String;
    final address = (data?['clinicAddress'] ?? 'Plot 42, Sunrise Healthcare Complex, Mumbai - 400001') as String;
    final phone = (data?['clinicPhone'] ?? user?.phoneNumber ?? '+91 91520 35527') as String;
    final email = (data?['clinicEmail'] ?? user?.email ?? 'care@crudoc.com') as String;
    final tagline = (data?['letterheadTagline'] ?? 'Excellence in Healthcare & Patient Wellbeing') as String;
    final footer = (data?['letterheadFooterDisclaimer'] ?? 'This digital document is generated by CruDoc Practice Management System.') as String;
    final logoUrl = data?['clinicLogoUrl'] as String?;

    return DoctorLetterheadConfig(
      clinicName: clinicName,
      doctorName: doctorName,
      qualifications: qualifications,
      registrationNumber: regNo,
      specialty: specialty,
      clinicAddress: address,
      clinicPhone: phone,
      clinicEmail: email,
      tagline: tagline,
      footerDisclaimer: footer,
      logoUrl: logoUrl,
    );
  }
}

