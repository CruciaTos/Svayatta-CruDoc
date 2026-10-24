import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';

import '../data/branding_image_store.dart';
import '../data/doc_repository.dart';
import '../data/doc_settings_models.dart';
import '../models/pdf_document_models.dart';
import '../templates/doc_template.dart';
import 'doc_context.dart';
import 'pdf_text.dart';

/// The uid to record as signer: the signed-in user, but only when they
/// are the issuing doctor (and a doctor). Null otherwise.
String? docSignerFor(String? issuingDoctorUid) {
  final me = FirebaseAuth.instance.currentUser?.uid;
  if (me == null || issuingDoctorUid == null || me != issuingDoctorUid) {
    return null;
  }
  final member = ClinicSession.instance.member;
  if (member != null && member.kind != MemberKind.doctor) {
    return null;
  }
  return me;
}

/// Who a new document is for when nobody picked: the signed-in doctor;
/// a solo user (no clinic access) is their own doctor; staff → null.
String? defaultIssuingDoctorUid() {
  final me = FirebaseAuth.instance.currentUser?.uid;
  if (me == null) return null;
  final member = ClinicSession.instance.member;
  if (member != null) {
    return member.kind == MemberKind.doctor ? me : null;
  }
  return me;
}

Future<DocContext> buildDocContext({
  required PdfMedicalDocumentData data,
  required DocTemplate template,
  bool sample = false,
}) async {
  final me = FirebaseAuth.instance.currentUser?.uid;
  final tenant = DocRepository.instance.tenantOrNull;
  final iAmOwner = me != null && (tenant == null || me == tenant);

  // 0. Legacy letterhead fallback
  final hasCallerConfig =
      data.letterheadConfig.clinicName.trim().isNotEmpty ||
      data.letterheadConfig.doctorName.trim().isNotEmpty;
  final DoctorLetterheadConfig legacy;
  if (hasCallerConfig) {
    legacy = data.letterheadConfig;
  } else {
    final legacyProfile = await DocRepository.instance.myLegacyProfileOnce();
    legacy = DoctorLetterheadConfig.fromProfileData(
      legacyProfile,
      FirebaseAuth.instance.currentUser,
    );
  }

  // 1. Clinic settings
  final settings = await DocRepository.instance.clinicSettingsOnce();
  final canFallbackClinic = iAmOwner || hasCallerConfig;
  String fallback(String current, String leg) => current.trim().isNotEmpty
      ? current.trim()
      : (canFallbackClinic ? leg.trim() : '');

  final clinic = DocClinicInfo(
    name: fallback(settings.name, legacy.clinicName),
    tagline: fallback(settings.tagline, legacy.tagline),
    address: fallback(settings.address, legacy.clinicAddress),
    phone: fallback(settings.phone, legacy.clinicPhone),
    email: fallback(settings.email, legacy.clinicEmail),
    website: settings.website.trim(),
    timings: settings.timings.trim(),
    regNo: settings.regNo.trim(),
    gstin: settings.gstin.trim(),
    footerText: fallback(settings.footerText, legacy.footerDisclaimer),
    termsText: settings.termsText.trim(),
    upiId: settings.upiId.trim(),
    upiName: settings.upiName.trim(),
    gstEnabled: settings.gstEnabled,
    roundOff: settings.roundOff,
  );

  // 2. Doctor details
  final uid = data.issuingDoctorUid ?? defaultIssuingDoctorUid();
  DocDoctorInfo? doctor;
  DoctorDocProfile? doctorProfile;
  if (uid != null && uid.isNotEmpty) {
    doctorProfile = await DocRepository.instance.doctorProfileOnce(uid);
    final member = await DocRepository.instance.memberOnce(uid);

    String resolveProp(String profVal, Object? memberVal, String legVal) {
      if (profVal.trim().isNotEmpty) {
        return profVal.trim();
      }
      if (memberVal is String && memberVal.trim().isNotEmpty) {
        return memberVal.trim();
      }
      if (uid == me && legVal.trim().isNotEmpty) {
        return legVal.trim();
      }
      return '';
    }

    final dName = resolveProp(
      doctorProfile?.nameOnDocs ?? '',
      member?['name'],
      legacy.doctorName,
    );
    final dQual = resolveProp(
      doctorProfile?.qualification ?? '',
      member?['qualification'],
      legacy.qualifications,
    );
    final dReg = resolveProp(
      doctorProfile?.regNo ?? '',
      member?['registrationNo'],
      legacy.registrationNumber,
    );
    final dSpec = resolveProp(
      doctorProfile?.specialty ?? '',
      member?['specialty'],
      legacy.specialty,
    );
    final dCouncil = doctorProfile?.regCouncil.trim() ?? '';
    final dPhone = resolveProp(
      doctorProfile?.phone ?? '',
      member?['phone'],
      '',
    );
    final dEmail = resolveProp(
      doctorProfile?.email ?? '',
      member?['email'],
      '',
    );
    final active = member == null || member['active'] != false;

    if (dName.isNotEmpty ||
        dQual.isNotEmpty ||
        dReg.isNotEmpty ||
        dSpec.isNotEmpty) {
      doctor = DocDoctorInfo(
        uid: uid,
        name: dName,
        qualification: dQual,
        specialty: dSpec,
        regNo: dReg,
        regCouncil: dCouncil,
        phone: dPhone,
        email: dEmail,
        active: active,
      );
    }
  }

  // 3. Active clinic doctors (for doctorList blocks)
  final hasDoctorListBlock = template.blocks.any(
    (b) => !b.hidden && b.type == DocBlockType.doctorList,
  );
  final doctors = <DocDoctorInfo>[];
  if (hasDoctorListBlock) {
    final activeMembers = await DocRepository.instance.activeDoctorsOnce();
    activeMembers.sort((a, b) => a.name.compareTo(b.name));
    for (final m in activeMembers.take(4)) {
      final p = await DocRepository.instance.doctorProfileOnce(m.uid);
      doctors.add(
        DocDoctorInfo(
          uid: m.uid,
          name: (p?.nameOnDocs.trim().isNotEmpty == true)
              ? p!.nameOnDocs.trim()
              : m.name,
          qualification: (p?.qualification.trim().isNotEmpty == true)
              ? p!.qualification.trim()
              : m.qualification,
          specialty: (p?.specialty.trim().isNotEmpty == true)
              ? p!.specialty.trim()
              : m.specialty,
          regNo: (p?.regNo.trim().isNotEmpty == true)
              ? p!.regNo.trim()
              : m.registrationNo,
          regCouncil: p?.regCouncil.trim() ?? '',
          phone: m.phone,
          email: m.email,
          active: m.active,
        ),
      );
    }
  }

  // 4. Images
  final warnings = <DocWarning>[];

  Future<Uint8List?> loadImg(
    String path,
    String sha,
    String label,
    DocFix fix,
  ) async {
    if (path.isEmpty || sha.isEmpty) return null;
    final res = await BrandingImageStore.instance.load(path, sha);
    if (res.problem == BrandingImageProblem.notDownloaded) {
      warnings.add(
        DocWarning(
          '$label not downloaded yet — connect to the internet once',
          fix: fix,
        ),
      );
    } else if (res.problem == BrandingImageProblem.mismatch) {
      warnings.add(
        DocWarning(
          'Your $label file was changed outside CruDoc and was left out. Upload it again in Settings › Clinic & documents.',
          fix: fix,
        ),
      );
    }
    return res.bytes;
  }

  final logo = await loadImg(
    settings.logoPath,
    settings.logoSha,
    'Logo',
    DocFix.clinicDetails,
  );
  final clinicStamp = await loadImg(
    settings.clinicStampPath,
    settings.clinicStampSha,
    'Clinic stamp',
    DocFix.clinicDetails,
  );
  final background = template.background != null
      ? await loadImg(
          template.background!.path,
          template.background!.sha,
          'Background',
          DocFix.clinicDetails,
        )
      : null;

  Uint8List? signature;
  Uint8List? stamp;
  if (doctor != null &&
      doctor.active &&
      data.signedByUid != null &&
      data.signedByUid == doctor.uid &&
      doctorProfile != null) {
    signature = await loadImg(
      doctorProfile.signaturePath,
      doctorProfile.signatureSha,
      'Signature',
      DocFix.myDetails,
    );
    stamp = await loadImg(
      doctorProfile.stampPath,
      doctorProfile.stampSha,
      'Stamp',
      DocFix.myDetails,
    );
  }

  final custom = <String, Uint8List>{};
  for (final b in template.blocks) {
    if (b.type == DocBlockType.image && b.imageRole == DocImageRole.custom) {
      if (b.imagePath.isNotEmpty &&
          b.imageSha.isNotEmpty &&
          !custom.containsKey(b.imageSha)) {
        final imgBytes = await loadImg(
          b.imagePath,
          b.imageSha,
          'Custom image',
          DocFix.none,
        );
        if (imgBytes != null) {
          custom[b.imageSha] = imgBytes;
        }
      }
    }
  }

  final images = DocImages(
    logo: logo,
    signature: signature,
    stamp: stamp,
    clinicStamp: clinicStamp,
    background: background,
    custom: custom,
  );

  // 5. Warnings for missing details (only when not sample)
  if (!sample) {
    if (clinic.name.isEmpty) {
      warnings.add(
        const DocWarning('Add your clinic name', fix: DocFix.clinicDetails),
      );
    }
    final kind = data.kind;
    if (kind == DocKind.prescription ||
        kind == DocKind.certificate ||
        kind == DocKind.referral) {
      if (doctor == null || doctor.regNo.isEmpty) {
        warnings.add(
          const DocWarning(
            'Add your registration number — it must be on prescriptions and certificates',
            fix: DocFix.myDetails,
          ),
        );
      }
    }
    if (template.tooNew) {
      warnings.add(
        DocWarning('Update CruDoc to use the template ‘${template.name}’'),
      );
    }
    final textsToCheck = [
      data.patient.fullName,
      clinic.name,
      clinic.address,
      doctor?.name ?? '',
    ];
    if (textsToCheck.any(needsScriptFallback)) {
      warnings.add(
        const DocWarning(
          'Some Indian-language text may not print correctly yet',
        ),
      );
    }
  }

  return DocContext(
    data: data,
    clinic: clinic,
    doctor: doctor,
    doctors: doctors,
    images: images,
    sample: sample,
    warnings: warnings,
  );
}
