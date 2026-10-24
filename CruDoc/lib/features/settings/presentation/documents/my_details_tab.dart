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
      builder: (ctx) => AlertDialog(
        backgroundColor: context.cru.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CruRadius.card),
        ),
        title: Text('Draw signature', style: CruType.headline),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SignaturePad(controller: padController, height: 180),
              const SizedBox(height: CruSpace.s12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CruButton(
                    label: 'Clear',
                    kind: CruButtonKind.secondary,
                    onPressed: padController.clear,
                  ),
                  const SizedBox(width: CruSpace.s8),
                  CruButton(
                    label: 'Use signature',
                    onPressed: () async {
                      final png = await padController.toPng();
                      if (ctx.mounted) Navigator.pop(ctx, png);
                    },
                  ),
                ],
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
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: ctx.cru.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CruRadius.card),
            ),
            title: Text('Signature preview', style: CruType.headline),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 320,
                  height: 120,
                  decoration: ShapeDecoration(
                    color: Colors.white,
                    shape: cruShape(
                      CruRadius.control,
                      side: BorderSide(color: ctx.cru.hairline),
                    ),
                  ),
                  child: Image.memory(currentPng, fit: BoxFit.contain),
                ),
                const SizedBox(height: CruSpace.s16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Keep original background'),
                  subtitle: const Text('Turn on if lines are too faint'),
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
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Use signature'),
              ),
            ],
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
    final c = context.cru;
    final profileAsync = ref.watch(myDocProfileProvider);
    profileAsync.whenData((prof) {
      if (!_loaded) _loadInitial(prof);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Doctor identity card
        CruCard(
          semanticLabel: 'Doctor identity details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Doctor details', style: CruType.headline.tint(c.label)),
              const SizedBox(height: CruSpace.s4),
              Text(
                'Printed on documents you issue (prescriptions, certificates, referrals, bills).',
                style: CruType.text.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Name on documents',
                controller: _nameOnDocs,
                hint: 'Dr. John Doe',
              ),
              const SizedBox(height: CruSpace.s16),
              CruFieldRow(
                children: [
                  CruTextField(
                    label: 'Qualifications',
                    controller: _qualification,
                    hint: 'MBBS, MD (General Medicine)',
                  ),
                  CruTextField(
                    label: 'Specialty',
                    controller: _specialty,
                    optional: true,
                    hint: 'Cardiology',
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s16),
              CruFieldRow(
                children: [
                  CruTextField(
                    label: 'Registration number',
                    controller: _regNo,
                    hint: 'MMC 2018/06/1234',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCouncil,
                    decoration: InputDecoration(
                      labelText: 'State / Medical council',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: CruSpace.s12,
                        vertical: CruSpace.s10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(CruRadius.control),
                      ),
                    ),
                    items: [
                      for (final council in _indianCouncils)
                        DropdownMenuItem(
                          value: council,
                          child: Text(council, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedCouncil = v);
                    },
                  ),
                ],
              ),
              if (_selectedCouncil == 'Other') ...[
                const SizedBox(height: CruSpace.s16),
                CruTextField(
                  label: 'Council name',
                  controller: _customCouncil,
                  hint: 'Medical Council of India',
                ),
              ],
              const SizedBox(height: CruSpace.s16),
              CruFieldRow(
                children: [
                  CruTextField(
                    label: 'Direct phone',
                    controller: _phone,
                    optional: true,
                    keyboardType: TextInputType.phone,
                  ),
                  CruTextField(
                    label: 'Direct email',
                    controller: _email,
                    optional: true,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Standard consultation fee (₹)',
                controller: _consultFee,
                optional: true,
                keyboardType: TextInputType.number,
                hint: '500',
                help:
                    'Prefills a consultation line when you create a new bill.',
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.cardGap),

        // Signature & Stamp
        CruCard(
          semanticLabel: 'Signature and stamp',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Signature & stamp', style: CruType.headline.tint(c.label)),
              const SizedBox(height: CruSpace.s16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Signature
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your signature',
                          style: CruType.subhead.w500.tint(c.label),
                        ),
                        const SizedBox(height: CruSpace.s8),
                        Container(
                          width: double.infinity,
                          height: 100,
                          decoration: ShapeDecoration(
                            color: Colors.white,
                            shape: cruShape(
                              CruRadius.control,
                              side: BorderSide(color: c.hairline),
                            ),
                          ),
                          child: _signatureBytes != null
                              ? Image.memory(
                                  _signatureBytes!,
                                  fit: BoxFit.contain,
                                )
                              : Center(
                                  child: Text(
                                    'No signature saved',
                                    style: CruType.text.tint(c.label2),
                                  ),
                                ),
                        ),
                        const SizedBox(height: CruSpace.s12),
                        Wrap(
                          spacing: CruSpace.s8,
                          runSpacing: CruSpace.s8,
                          children: [
                            CruButton(
                              label: 'Draw',
                              kind: CruButtonKind.secondary,
                              onPressed: _drawSignature,
                            ),
                            CruButton(
                              label: 'Upload photo',
                              kind: CruButtonKind.secondary,
                              onPressed: _uploadSignaturePhoto,
                            ),
                            if (_signatureBytes != null)
                              CruLink(
                                label: 'Remove',
                                style: CruType.subhead.tint(c.redText),
                                onPressed: () {
                                  setState(() {
                                    _signaturePath = '';
                                    _signatureSha = '';
                                    _signatureBytes = null;
                                  });
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: CruSpace.s8),
                        Text(
                          'Only you can change your signature. It is printed only on documents you create.',
                          style: CruType.caption.tint(c.label2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: CruSpace.s24),

                  // Personal Stamp
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Personal stamp',
                          style: CruType.subhead.w500.tint(c.label),
                        ),
                        const SizedBox(height: CruSpace.s8),
                        Container(
                          width: double.infinity,
                          height: 100,
                          decoration: ShapeDecoration(
                            color: Colors.white,
                            shape: cruShape(
                              CruRadius.control,
                              side: BorderSide(color: c.hairline),
                            ),
                          ),
                          child: _stampBytes != null
                              ? Image.memory(_stampBytes!, fit: BoxFit.contain)
                              : Center(
                                  child: Text(
                                    'No stamp saved',
                                    style: CruType.text.tint(c.label2),
                                  ),
                                ),
                        ),
                        const SizedBox(height: CruSpace.s12),
                        Wrap(
                          spacing: CruSpace.s8,
                          children: [
                            CruButton(
                              label: _stampBytes == null ? 'Upload' : 'Replace',
                              kind: CruButtonKind.secondary,
                              onPressed: _uploadStamp,
                            ),
                            if (_stampBytes != null)
                              CruLink(
                                label: 'Remove',
                                style: CruType.subhead.tint(c.redText),
                                onPressed: () {
                                  setState(() {
                                    _stampPath = '';
                                    _stampSha = '';
                                    _stampBytes = null;
                                  });
                                },
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.s24),

        // Save
        Align(
          alignment: Alignment.centerRight,
          child: CruButton(
            label: _saving ? 'Saving…' : 'Save doctor details',
            onPressed: _saving ? null : _save,
          ),
        ),
        const SizedBox(height: CruSpace.s32),
      ],
    );
  }
}
