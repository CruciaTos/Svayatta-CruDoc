import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:doctor_management_app/core/pdf/data/branding_image_store.dart';
import 'package:doctor_management_app/core/pdf/data/doc_repository.dart';
import 'package:doctor_management_app/core/pdf/data/doc_settings_models.dart';
import 'package:doctor_management_app/core/services/medical_storage_service.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/doctor_identity_provider.dart';
import 'package:doctor_management_app/features/settings/presentation/documents/documents_kit.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';
import 'package:doctor_management_app/shared/widgets/signature_pad.dart';

const List<String> _indianCouncils = [
  'National Medical Commission (NMC)',
  'Dental Council of India (DCI)',
  'Andhra Pradesh Medical Council',
  'Assam Medical Council',
  'Bihar Medical Council',
  'Chhattisgarh Medical Council',
  'Delhi Medical Council',
  'Goa Medical Council',
  'Gujarat Medical Council',
  'Haryana Medical Council',
  'Himachal Pradesh Medical Council',
  'Jammu & Kashmir Medical Council',
  'Jharkhand Medical Council',
  'Karnataka Medical Council',
  'Kerala Medical Council',
  'Madhya Pradesh Medical Council',
  'Maharashtra Medical Council (MMC)',
  'Maharashtra Dental Council (MDC)',
  'Manipur Medical Council',
  'Mizoram Medical Council',
  'Nagaland Medical Council',
  'Odisha Medical Council',
  'Punjab Medical Council',
  'Rajasthan Medical Council',
  'Sikkim Medical Council',
  'Tamil Nadu Medical Council',
  'Telangana State Medical Council',
  'Tripura Medical Council',
  'Uttar Pradesh Medical Council',
  'Uttarakhand Medical Council',
  'West Bengal Medical Council',
  'Other',
];

class MyDetailsTab extends ConsumerStatefulWidget {
  const MyDetailsTab({super.key});

  @override
  ConsumerState<MyDetailsTab> createState() => _MyDetailsTabState();
}

class _MyDetailsTabState extends ConsumerState<MyDetailsTab> {
  final _nameOnDocs = TextEditingController();
  final _qualification = TextEditingController();
  final _specialty = TextEditingController();
  final _regNo = TextEditingController();
  final _customCouncil = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _consultFee = TextEditingController();

  String _selectedCouncil = _indianCouncils.first;

  String _signaturePath = '';
  String _signatureSha = '';
  Uint8List? _signatureBytes;

  String _stampPath = '';
  String _stampSha = '';
  Uint8List? _stampBytes;

  bool _loaded = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameOnDocs.dispose();
    _qualification.dispose();
    _specialty.dispose();
    _regNo.dispose();
    _customCouncil.dispose();
    _phone.dispose();
    _email.dispose();
    _consultFee.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadInitial(DoctorDocProfile? prof) async {
    if (_loaded) return;
    _loaded = true;

    final user = FirebaseAuth.instance.currentUser;
    final me = user?.uid ?? '';

    if (prof != null) {
      _nameOnDocs.text = prof.nameOnDocs;
      _qualification.text = prof.qualification;
      _specialty.text = prof.specialty;
      _regNo.text = prof.regNo;
      _phone.text = prof.phone;
      _email.text = prof.email;
      if (prof.consultFeePaise > 0) {
        _consultFee.text = (prof.consultFeePaise / 100).toStringAsFixed(0);
      }
      _signaturePath = prof.signaturePath;
      _signatureSha = prof.signatureSha;
      _stampPath = prof.stampPath;
      _stampSha = prof.stampSha;

      if (_indianCouncils.contains(prof.regCouncil)) {
        _selectedCouncil = prof.regCouncil;
      } else if (prof.regCouncil.isNotEmpty) {
        _selectedCouncil = 'Other';
        _customCouncil.text = prof.regCouncil;
      }
    }

    // Prefills from user / member / legacy profile if empty
    if (_nameOnDocs.text.isEmpty) {
      final profMap = ref.read(doctorProfileProvider).value;
      final formatted = DoctorProfileHelper.formatDoctorName(user, profMap);
      _nameOnDocs.text = formatted.startsWith('Dr.')
          ? formatted
          : 'Dr. $formatted';
    }

    final member = await DocRepository.instance.memberOnce(me);
    if (member != null) {
      if (_qualification.text.isEmpty && member['qualification'] is String) {
        _qualification.text = (member['qualification'] as String).trim();
      }
      if (_regNo.text.isEmpty && member['registrationNo'] is String) {
        _regNo.text = (member['registrationNo'] as String).trim();
      }
      if (_specialty.text.isEmpty && member['specialty'] is String) {
        _specialty.text = (member['specialty'] as String).trim();
      }
    }

    final legacy = await DocRepository.instance.myLegacyProfileOnce();
    if (legacy != null) {
      String read(List<String> keys, [String? fallback]) {
        for (final k in keys) {
          final v = legacy[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return fallback ?? '';
      }

      if (_qualification.text.isEmpty) {
        _qualification.text = read(['qualifications', 'doctorQualifications']);
      }
      if (_regNo.text.isEmpty) {
        _regNo.text = read(['registrationNumber', 'doctorRegistrationNumber']);
      }
      if (_phone.text.isEmpty) {
        _phone.text = read(['clinicPhone'], user?.phoneNumber);
      }
      if (_email.text.isEmpty) _email.text = read(['clinicEmail'], user?.email);
    }

    // Load signature and stamp bytes
    if (_signatureSha.isNotEmpty) {
      final res = await BrandingImageStore.instance.load(
        _signaturePath,
        _signatureSha,
      );
      if (mounted && res.bytes != null) {
        setState(() => _signatureBytes = res.bytes);
      }
    }
    if (_stampSha.isNotEmpty) {
      final res = await BrandingImageStore.instance.load(_stampPath, _stampSha);
      if (mounted && res.bytes != null) {
        setState(() => _stampBytes = res.bytes);
      }
    }

    if (mounted) setState(() {});
  }

  Future<Uint8List?> _pickImage() async {
    try {
      if (kIsWeb ||
          Platform.isWindows ||
          Platform.isMacOS ||
          Platform.isLinux) {
        final res = await FilePicker.pickFiles(
          dialogTitle: 'Select image',
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
          withData: true,
        );
        if (res != null && res.files.isNotEmpty) {
          final f = res.files.first;
          if (f.bytes != null) return f.bytes;
          if (f.path != null) return await File(f.path!).readAsBytes();
        }
        return null;
      } else {
        final picker = ImagePicker();
        final picked = await picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 95,
        );
        if (picked != null) {
          return await picked.readAsBytes();
        }
        return null;
      }
    } catch (e) {
      _toast('Could not pick image: $e');
      return null;
    }
  }

  Future<void> _drawSignature() async {
    final padController = SignatureController();
    final drawn = await showDialog<Uint8List>(
      context: context,
      builder: (ctx) => CruFormDialog(
        title: 'Draw your signature',
        subtitle: 'Sign with your finger, a pen or the mouse.',
        leading: const CruIconTile(
          icon: CruIcons.pen,
          tone: CruTileTone.neutral,
        ),
        submitLabel: 'Use signature',
        width: CruSize.dialog + CruSpace.s32 * 3,
        onSubmit: () async {
          final png = await padController.toPng();
          if (ctx.mounted) Navigator.pop(ctx, png);
        },
        body: Padding(
          padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The white pad on an inset tray, so its edge shows.
              Container(
                padding: const EdgeInsets.all(CruSpace.s6),
                decoration: ShapeDecoration(
                  color: ctx.cru.inset,
                  shape: cruShape(CruRadius.control + CruSpace.s6),
                ),
                child: SignaturePad(controller: padController, height: 180),
              ),
              const SizedBox(height: CruSpace.s12),
              Align(
                alignment: Alignment.centerRight,
                child: CruButton(
                  label: 'Clear',
                  kind: CruButtonKind.inset,
                  onPressed: padController.clear,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (drawn == null) return;

    try {
      final png = await prepareBrandingImage(drawn, maxSide: 1000);
      await _uploadSignatureBytes(png);
    } catch (e) {
      _toast('Failed to process signature: $e');
    }
  }

  Future<void> _uploadSignaturePhoto() async {
    final raw = await _pickImage();
    if (raw == null) return;

    try {
      Uint8List currentPng = await prepareBrandingImage(
        raw,
        maxSide: 1000,
        cleanBackground: true,
      );
      bool keepBg = false;

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => CruFormDialog(
            title: 'Check your signature',
            subtitle: 'This is how it prints on your documents.',
            leading: const CruIconTile(
              icon: CruIcons.pen,
              tone: CruTileTone.neutral,
            ),
            submitLabel: 'Use signature',
            width: CruSize.dialog + CruSpace.s32 * 2,
            onSubmit: () => Navigator.pop(ctx, true),
            body: Padding(
              padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 120,
                    padding: const EdgeInsets.all(CruSpace.s12),
                    decoration: ShapeDecoration(
                      // Printed on white paper in both appearances.
                      color: CruBrand.white,
                      shape: cruShape(
                        CruRadius.control,
                        side: BorderSide(color: ctx.cru.separator),
                      ),
                    ),
                    child: Image.memory(
                      currentPng,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                  const SizedBox(height: CruSpace.s16),
                  DocToggleRow(
                    title: 'Keep the original background',
                    subtitle: 'Turn on if the lines look too faint.',
                    value: keepBg,
                    onChanged: (v) async {
                      setDialogState(() => keepBg = v);
                      final updated = await prepareBrandingImage(
                        raw,
                        maxSide: 1000,
                        cleanBackground: !v,
                      );
                      setDialogState(() => currentPng = updated);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (confirmed == true) {
        await _uploadSignatureBytes(currentPng);
      }
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Failed to process signature photo: $e');
    }
  }

  Future<void> _uploadSignatureBytes(Uint8List png) async {
    final tenant = DocRepository.instance.tenantOrNull;
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (tenant == null || me == null) {
      _toast('No active clinic');
      return;
    }
    final sha = sha256Hex(png);
    try {
      final stored = await MedicalStorageService.instance.uploadDoctorFile(
        doctorId: tenant,
        uid: me,
        relativePath: 'signature',
        png: png,
      );
      await BrandingImageStore.instance.remember(sha, png);
      setState(() {
        _signaturePath = stored.path;
        _signatureSha = sha;
        _signatureBytes = png;
      });
      _toast('Signature updated');
    } catch (_) {
      _toast('Connect to the internet to upload');
    }
  }

  Future<void> _uploadStamp() async {
    final raw = await _pickImage();
    if (raw == null) return;
    try {
      final png = await prepareBrandingImage(raw, maxSide: 1000);
      final sha = sha256Hex(png);
      final tenant = DocRepository.instance.tenantOrNull;
      final me = FirebaseAuth.instance.currentUser?.uid;
      if (tenant == null || me == null) throw StateError('No active clinic');

      final stored = await MedicalStorageService.instance.uploadDoctorFile(
        doctorId: tenant,
        uid: me,
        relativePath: 'stamp',
        png: png,
      );
      await BrandingImageStore.instance.remember(sha, png);
      setState(() {
        _stampPath = stored.path;
        _stampSha = sha;
        _stampBytes = png;
      });
      _toast('Personal stamp updated');
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Connect to the internet to upload');
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final user = FirebaseAuth.instance.currentUser;
    final me = user?.uid;
    final tenant = DocRepository.instance.tenantOrNull;

    if (me == null || tenant == null) {
      _toast('Not signed in');
      setState(() => _saving = false);
      return;
    }

    try {
      final feeNum = double.tryParse(_consultFee.text.trim()) ?? 0;
      final feePaise = (feeNum * 100).round();
      final council = _selectedCouncil == 'Other'
          ? _customCouncil.text.trim()
          : _selectedCouncil;

      final current =
          await DocRepository.instance.doctorProfileOnce(me) ??
          DoctorDocProfile(uid: me);

      final updated = current.copyWith(
        nameOnDocs: _nameOnDocs.text.trim(),
        qualification: _qualification.text.trim(),
        specialty: _specialty.text.trim(),
        regNo: _regNo.text.trim(),
        regCouncil: council,
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        consultFeePaise: feePaise,
        signaturePath: _signaturePath,
        signatureSha: _signatureSha,
        stampPath: _stampPath,
        stampSha: _stampSha,
      );

      await DocRepository.instance.saveMyProfile(updated);

      // Keep the team list in step. The rules let a member change only
      // these keys on their own record (no updatedAt), and a solo doctor
      // has no member record at all, so update, never create.
      try {
        await FirebaseFirestore.instance
            .collection('clinics')
            .doc(tenant)
            .collection('members')
            .doc(me)
            .update({
              'qualification': _qualification.text.trim(),
              'registrationNo': _regNo.text.trim(),
            });
      } catch (_) {}

      // Older screens (the radiology report) read the doctor's own profile.
      // Only the doctor's fields: the clinic fields there are the fallback
      // for clinic details and must not be blanked from here.
      try {
        await FirebaseFirestore.instance.collection('users').doc(me).set({
          'qualifications': _qualification.text.trim(),
          'doctorQualifications': _qualification.text.trim(),
          'registrationNumber': _regNo.text.trim(),
          'doctorRegistrationNumber': _regNo.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}

      _toast('Doctor details saved.');
    } catch (e) {
      _toast('Failed to save details: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myDocProfileProvider);
    profileAsync.whenData((prof) {
      if (!_loaded) _loadInitial(prof);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Who signs
        CruCard(
          semanticLabel: 'Doctor details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DocCardHeader(
                title: 'Doctor details',
                description:
                    'Printed on the prescriptions, certificates, referrals '
                    'and bills you issue.',
              ),
              const SizedBox(height: CruSpace.s20),
              CruTextField(
                label: 'Name on documents',
                controller: _nameOnDocs,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: CruSpace.s16),
              DocFieldPair(
                first: CruTextField(
                  label: 'Qualifications',
                  controller: _qualification,
                  hint: 'e.g. MBBS, MD',
                ),
                second: CruTextField(
                  label: 'Specialty',
                  controller: _specialty,
                  optional: true,
                  textCapitalization: TextCapitalization.words,
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              DocFieldPair(
                first: CruTextField(
                  label: 'Registration number',
                  controller: _regNo,
                  tabular: true,
                ),
                second: CruDropdownField<String>(
                  label: 'Medical council',
                  value: _selectedCouncil,
                  items: _indianCouncils,
                  itemLabel: (council) => council,
                  onChanged: (v) => setState(() => _selectedCouncil = v),
                ),
              ),
              if (_selectedCouncil == 'Other') ...[
                const SizedBox(height: CruSpace.s16),
                DocFieldPair(
                  first: CruTextField(
                    label: 'Council name',
                    controller: _customCouncil,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ],
              const SizedBox(height: CruSpace.s16),
              DocFieldPair(
                first: CruTextField(
                  label: 'Direct phone',
                  controller: _phone,
                  optional: true,
                  tabular: true,
                  keyboardType: TextInputType.phone,
                ),
                second: CruTextField(
                  label: 'Direct email',
                  controller: _email,
                  optional: true,
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              DocFieldPair(
                first: CruTextField(
                  label: 'Consultation fee',
                  controller: _consultFee,
                  optional: true,
                  prefix: '₹',
                  tabular: true,
                  keyboardType: TextInputType.number,
                  help: 'Prefills a consultation line on every new bill.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.cardGap),

        // Signature & stamp
        CruCard(
          semanticLabel: 'Signature and stamp',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DocCardHeader(
                title: 'Signature & stamp',
                description:
                    'Only you can change these. They print only on documents '
                    'you create.',
              ),
              const SizedBox(height: CruSpace.s20),
              DocSplit(
                first: DocImageSlot(
                  title: 'Your signature',
                  caption: 'Draw it, or upload a photo of it on white paper.',
                  bytes: _signatureBytes,
                  emptyIcon: CruIcons.pen,
                  previewWidth: 120,
                  actions: [
                    CruButton(
                      label: 'Draw',
                      kind: CruButtonKind.inset,
                      onPressed: _drawSignature,
                    ),
                    CruButton(
                      label: 'Upload photo',
                      kind: CruButtonKind.inset,
                      onPressed: _uploadSignaturePhoto,
                    ),
                  ],
                  onRemove: () => setState(() {
                    _signaturePath = '';
                    _signatureSha = '';
                    _signatureBytes = null;
                  }),
                ),
                second: DocImageSlot(
                  title: 'Personal stamp',
                  caption: 'Your registration stamp, if you use one.',
                  bytes: _stampBytes,
                  emptyIcon: DocIcons.stamp,
                  previewWidth: 120,
                  actions: [
                    CruButton(
                      label: _stampBytes == null ? 'Upload' : 'Replace',
                      kind: CruButtonKind.inset,
                      onPressed: _uploadStamp,
                    ),
                  ],
                  onRemove: () => setState(() {
                    _stampPath = '';
                    _stampSha = '';
                    _stampBytes = null;
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.s24),

        DocSaveBar(
          label: 'Save doctor details',
          saving: _saving,
          onSave: _save,
        ),
        const SizedBox(height: CruSpace.s32),
      ],
    );
  }
}
