import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/pdf/data/branding_image_store.dart';
import 'package:doctor_management_app/core/pdf/data/doc_numbering.dart';
import 'package:doctor_management_app/core/pdf/data/doc_repository.dart';
import 'package:doctor_management_app/core/pdf/data/doc_settings_models.dart';
import 'package:doctor_management_app/core/pdf/render/pdf_text.dart';
import 'package:doctor_management_app/core/pdf/templates/doc_template.dart';
import 'package:doctor_management_app/core/services/medical_storage_service.dart';
import 'package:doctor_management_app/core/utils/doctor_profile_helper.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

class ClinicDetailsTab extends ConsumerStatefulWidget {
  const ClinicDetailsTab({super.key});

  @override
  ConsumerState<ClinicDetailsTab> createState() => _ClinicDetailsTabState();
}

class _ClinicDetailsTabState extends ConsumerState<ClinicDetailsTab> {
  final _name = TextEditingController();
  final _tagline = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _website = TextEditingController();
  final _timings = TextEditingController();
  final _regNo = TextEditingController();
  final _footerText = TextEditingController();
  final _termsText = TextEditingController();

  final _gstin = TextEditingController();
  final _upiId = TextEditingController();
  final _upiName = TextEditingController();

  final Map<DocKind, TextEditingController> _prefixCtrls = {
    for (final k in DocKind.values) k: TextEditingController(),
  };

  bool _gstEnabled = false;
  bool _roundOff = true;
  bool _lockTemplates = false;

  String _logoPath = '';
  String _logoSha = '';
  Uint8List? _logoBytes;

  String _stampPath = '';
  String _stampSha = '';
  Uint8List? _stampBytes;

  bool _loaded = false;
  bool _saving = false;

  List<TextEditingController> get _allControllers => [
    _name,
    _tagline,
    _address,
    _phone,
    _email,
    _website,
    _timings,
    _regNo,
    _footerText,
    _termsText,
    _gstin,
    _upiId,
    _upiName,
    ..._prefixCtrls.values,
  ];

  @override
  void dispose() {
    for (final c in _allControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _loadInitial(ClinicDocSettings s) async {
    if (_loaded) return;
    _loaded = true;

    _name.text = s.name;
    _tagline.text = s.tagline;
    _address.text = s.address;
    _phone.text = s.phone;
    _email.text = s.email;
    _website.text = s.website;
    _timings.text = s.timings;
    _regNo.text = s.regNo;
    _footerText.text = s.footerText;
    _termsText.text = s.termsText;
    _gstin.text = s.gstin;
    _upiId.text = s.upiId;
    _upiName.text = s.upiName;
    _gstEnabled = s.gstEnabled;
    _roundOff = s.roundOff;
    _lockTemplates = s.lockTemplates;
    _logoPath = s.logoPath;
    _logoSha = s.logoSha;
    _stampPath = s.clinicStampPath;
    _stampSha = s.clinicStampSha;

    for (final k in DocKind.values) {
      _prefixCtrls[k]!.text = s.prefixes[k.name] ?? k.defaultPrefix;
    }

    // Fall back to owner's legacy profile for any empty values
    final legacy = await DocRepository.instance.myLegacyProfileOnce();
    if (legacy != null) {
      String read(List<String> keys) {
        for (final k in keys) {
          final v = legacy[k];
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
        return '';
      }

      if (_name.text.isEmpty) _name.text = read(['clinicName', 'practiceName']);
      if (_tagline.text.isEmpty) _tagline.text = read(['letterheadTagline']);
      if (_address.text.isEmpty) _address.text = read(['clinicAddress']);
      if (_phone.text.isEmpty) _phone.text = read(['clinicPhone']);
      if (_email.text.isEmpty) _email.text = read(['clinicEmail']);
      if (_footerText.text.isEmpty) {
        _footerText.text = read(['letterheadFooterDisclaimer']);
      }
    }

    // Load preview images if sha is present
    if (_logoSha.isNotEmpty) {
      final res = await BrandingImageStore.instance.load(_logoPath, _logoSha);
      if (mounted && res.bytes != null) {
        setState(() => _logoBytes = res.bytes);
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

  Future<void> _uploadLogo() async {
    final raw = await _pickImage();
    if (raw == null) return;
    try {
      final png = await prepareBrandingImage(raw, maxSide: 1000);
      final sha = sha256Hex(png);
      final tenant = DocRepository.instance.tenantOrNull;
      if (tenant == null) throw StateError('No active clinic');

      final stored = await MedicalStorageService.instance.uploadClinicBranding(
        doctorId: tenant,
        kind: ClinicBrandingKind.logo,
        bytes: png,
        contentType: 'image/png',
      );
      await BrandingImageStore.instance.remember(sha, png);
      setState(() {
        _logoPath = stored.path;
        _logoSha = sha;
        _logoBytes = png;
      });
      _toast('Logo uploaded');
    } on FormatException catch (e) {
      _toast(e.message);
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
      if (tenant == null) throw StateError('No active clinic');

      final stored = await MedicalStorageService.instance.uploadClinicBranding(
        doctorId: tenant,
        kind: ClinicBrandingKind.clinicStamp,
        bytes: png,
        contentType: 'image/png',
      );
      await BrandingImageStore.instance.remember(sha, png);
      setState(() {
        _stampPath = stored.path;
        _stampSha = sha;
        _stampBytes = png;
      });
      _toast('Clinic stamp uploaded');
    } on FormatException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('Connect to the internet to upload');
    }
  }

  Future<void> _syncClinicName(String name) async {
    final access = ClinicSession.instance.access;
    if (access == null || !access.isOwner || name.isEmpty) return;
    try {
      final clinic = FirebaseFirestore.instance
          .collection('clinics')
          .doc(access.clinicId);
      if ((await clinic.get()).exists) {
        await clinic.update({
          'name': name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    // Validate prefixes
    for (final e in _prefixCtrls.entries) {
      final p = e.value.text.trim();
      if (p.isNotEmpty && !DocNumbering.isValidPrefix(p)) {
        _toast('Prefix for ${e.key.label} must be 1-5 letters or numbers.');
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final s = await DocRepository.instance.clinicSettingsOnce();
      final prefixes = <String, String>{
        for (final e in _prefixCtrls.entries)
          if (e.value.text.trim().isNotEmpty) e.key.name: e.value.text.trim(),
      };

      final updated = s.copyWith(
        name: _name.text.trim(),
        tagline: _tagline.text.trim(),
        address: _address.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        website: _website.text.trim(),
        timings: _timings.text.trim(),
        regNo: _regNo.text.trim(),
        footerText: _footerText.text.trim(),
        termsText: _termsText.text.trim(),
        gstin: _gstin.text.trim().toUpperCase(),
        upiId: _upiId.text.trim(),
        upiName: _upiName.text.trim(),
        gstEnabled: _gstEnabled,
        roundOff: _roundOff,
        lockTemplates: _lockTemplates,
        logoPath: _logoPath,
        logoSha: _logoSha,
        clinicStampPath: _stampPath,
        clinicStampSha: _stampSha,
        prefixes: prefixes,
      );

      await DocRepository.instance.saveClinicSettings(updated);

      final access = ClinicSession.instance.access;
      final isOwner = access == null || access.isOwner;
      if (isOwner) {
        final legacy = await DocRepository.instance.myLegacyProfileOnce();
        final docQual =
            (legacy?['qualifications'] ?? legacy?['doctorQualifications'] ?? '')
                as String;
        final regNo =
            (legacy?['registrationNumber'] ??
                    legacy?['doctorRegistrationNumber'] ??
                    '')
                as String;
        await DoctorProfileHelper.updateLetterheadBranding(
          clinicName: _name.text.trim(),
          doctorQualifications: docQual,
          registrationNumber: regNo,
          tagline: _tagline.text.trim(),
          clinicAddress: _address.text.trim(),
          clinicPhone: _phone.text.trim(),
          clinicEmail: _email.text.trim(),
          footerDisclaimer: _footerText.text.trim(),
        );
        await _syncClinicName(_name.text.trim());
      }

      _toast('Clinic details saved.');
    } catch (e) {
      _toast('Failed to save clinic details: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final access = ref.watch(clinicAccessProvider).value;
    final canEdit = access == null || access.can(ClinicPermission.settings);

    final settingsAsync = ref.watch(clinicDocSettingsProvider);
    settingsAsync.whenData((s) {
      if (!_loaded) _loadInitial(s);
    });

    final fy = financialYear(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!canEdit)
          Container(
            margin: const EdgeInsets.only(bottom: CruSpace.s16),
            padding: const EdgeInsets.all(CruSpace.s12),
            decoration: ShapeDecoration(
              color: c.surface,
              shape: cruShape(
                CruRadius.control,
                side: BorderSide(color: c.hairline),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, color: c.accentText, size: 16),
                const SizedBox(width: CruSpace.s8),
                Expanded(
                  child: Text(
                    'Only clinic admins can change these details.',
                    style: CruType.text.tint(c.label2),
                  ),
                ),
              ],
            ),
          ),

        // Clinic details card
        CruCard(
          semanticLabel: 'Clinic details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Clinic details', style: CruType.headline.tint(c.label)),
              const SizedBox(height: CruSpace.s16),
              CruFieldRow(
                children: [
                  CruTextField(
                    label: 'Clinic name',
                    controller: _name,
                    enabled: canEdit,
                    hint: 'Sanjeevani Clinic',
                  ),
                  CruTextField(
                    label: 'Tagline',
                    controller: _tagline,
                    enabled: canEdit,
                    optional: true,
                    hint: 'Family healthcare & wellbeing',
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Address (up to 3 lines)',
                controller: _address,
                enabled: canEdit,
                maxLines: 3,
                hint: 'Shop 4, Ground Floor\nNear Metro Station, Mumbai 400001',
              ),
              const SizedBox(height: CruSpace.s16),
              CruFieldRow(
                children: [
                  CruTextField(
                    label: 'Phone',
                    controller: _phone,
                    enabled: canEdit,
                    keyboardType: TextInputType.phone,
                  ),
                  CruTextField(
                    label: 'Email',
                    controller: _email,
                    enabled: canEdit,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s16),
              CruFieldRow(
                children: [
                  CruTextField(
                    label: 'Website',
                    controller: _website,
                    enabled: canEdit,
                    optional: true,
                    hint: 'https://example.com',
                  ),
                  CruTextField(
                    label: 'Clinic registration number',
                    controller: _regNo,
                    enabled: canEdit,
                    optional: true,
                    hint: 'CL-2024-001',
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Clinic timings (up to 2 lines)',
                controller: _timings,
                enabled: canEdit,
                optional: true,
                maxLines: 2,
                hint: 'Mon - Sat: 9:00 AM - 8:00 PM\nSun: 10:00 AM - 1:00 PM',
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.cardGap),

        // Logo & stamp
        CruCard(
          semanticLabel: 'Logo and clinic stamp',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Logo & clinic stamp',
                style: CruType.headline.tint(c.label),
              ),
              const SizedBox(height: CruSpace.s4),
              Text(
                'Used across documents. PNGs with transparent backgrounds look best.',
                style: CruType.text.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Clinic logo',
                          style: CruType.subhead.w500.tint(c.label),
                        ),
                        const SizedBox(height: CruSpace.s8),
                        Row(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: ShapeDecoration(
                                color: Colors.white,
                                shape: cruShape(
                                  CruRadius.control,
                                  side: BorderSide(color: c.hairline),
                                ),
                              ),
                              child: _logoBytes != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        CruRadius.control,
                                      ),
                                      child: Image.memory(
                                        _logoBytes!,
                                        fit: BoxFit.contain,
                                      ),
                                    )
                                  : Icon(
                                      Icons.image_outlined,
                                      color: c.label2,
                                      size: 28,
                                    ),
                            ),
                            const SizedBox(width: CruSpace.s12),
                            if (canEdit)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CruButton(
                                    label: _logoBytes == null
                                        ? 'Upload'
                                        : 'Replace',
                                    kind: CruButtonKind.secondary,
                                    onPressed: _uploadLogo,
                                  ),
                                  if (_logoBytes != null) ...[
                                    const SizedBox(height: CruSpace.s6),
                                    CruLink(
                                      label: 'Remove',
                                      style: CruType.subhead.tint(c.redText),
                                      onPressed: () {
                                        setState(() {
                                          _logoPath = '';
                                          _logoSha = '';
                                          _logoBytes = null;
                                        });
                                      },
                                    ),
                                  ],
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Clinic stamp
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Clinic stamp',
                          style: CruType.subhead.w500.tint(c.label),
                        ),
                        const SizedBox(height: CruSpace.s8),
                        Row(
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: ShapeDecoration(
                                color: Colors.white,
                                shape: cruShape(
                                  CruRadius.control,
                                  side: BorderSide(color: c.hairline),
                                ),
                              ),
                              child: _stampBytes != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(
                                        CruRadius.control,
                                      ),
                                      child: Image.memory(
                                        _stampBytes!,
                                        fit: BoxFit.contain,
                                      ),
                                    )
                                  : Icon(
                                      Icons.approval_outlined,
                                      color: c.label2,
                                      size: 28,
                                    ),
                            ),
                            const SizedBox(width: CruSpace.s12),
                            if (canEdit)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CruButton(
                                    label: _stampBytes == null
                                        ? 'Upload'
                                        : 'Replace',
                                    kind: CruButtonKind.secondary,
                                    onPressed: _uploadStamp,
                                  ),
                                  if (_stampBytes != null) ...[
                                    const SizedBox(height: CruSpace.s6),
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
                                ],
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
        const SizedBox(height: CruSpace.cardGap),

        // Bills
        CruCard(
          semanticLabel: 'Bill settings',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Bills & payments', style: CruType.headline.tint(c.label)),
              const SizedBox(height: CruSpace.s16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Charge GST on bills',
                  style: CruType.body.w500.tint(c.label),
                ),
                subtitle: Text(
                  'Splits into CGST and SGST on tax invoices',
                  style: CruType.subhead.tint(c.label2),
                ),
                value: _gstEnabled,
                onChanged: canEdit
                    ? (v) => setState(() => _gstEnabled = v)
                    : null,
              ),
              if (_gstEnabled) ...[
                const SizedBox(height: CruSpace.s12),
                CruTextField(
                  label: 'GSTIN (15 characters)',
                  controller: _gstin,
                  enabled: canEdit,
                  textCapitalization: TextCapitalization.characters,
                  hint: '27AAAAA0000A1Z5',
                ),
              ],
              const SizedBox(height: CruSpace.s16),
              CruFieldRow(
                children: [
                  CruTextField(
                    label: 'UPI ID for payments',
                    controller: _upiId,
                    enabled: canEdit,
                    optional: true,
                    hint: 'clinic@okhdfcbank',
                  ),
                  CruTextField(
                    label: 'Name shown when paying',
                    controller: _upiName,
                    enabled: canEdit,
                    optional: true,
                    hint: 'Sanjeevani Clinic',
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Round off to nearest rupee',
                  style: CruType.body.w500.tint(c.label),
                ),
                subtitle: Text(
                  'Eliminates paise from invoice grand totals',
                  style: CruType.subhead.tint(c.label2),
                ),
                value: _roundOff,
                onChanged: canEdit
                    ? (v) => setState(() => _roundOff = v)
                    : null,
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Bill terms & conditions',
                controller: _termsText,
                enabled: canEdit,
                optional: true,
                maxLines: 3,
                hint:
                    '1. Payment due upon receipt.\n2. Non-refundable consultation fee.\n3. Keep receipt for tax purposes.',
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.cardGap),

        // Numbering
        CruCard(
          semanticLabel: 'Document numbering',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Document numbering', style: CruType.headline.tint(c.label)),
              const SizedBox(height: CruSpace.s4),
              Text(
                'Sequential numbering per financial year (April - March).',
                style: CruType.text.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s16),
              for (final k in DocKind.values) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        k.label,
                        style: CruType.body.w500.tint(c.label),
                      ),
                    ),
                    const SizedBox(width: CruSpace.s12),
                    SizedBox(
                      width: 100,
                      child: CruTextField(
                        label: 'Prefix',
                        controller: _prefixCtrls[k]!,
                        enabled: canEdit,
                        textCapitalization: TextCapitalization.characters,
                        hint: k.defaultPrefix,
                      ),
                    ),
                    const SizedBox(width: CruSpace.s16),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: _prefixCtrls[k]!,
                        builder: (context, _) {
                          final p = _prefixCtrls[k]!.text.trim().isEmpty
                              ? k.defaultPrefix
                              : _prefixCtrls[k]!.text.trim().toUpperCase();
                          return Text(
                            'Next: $p-$fy/0001',
                            style: CruType.subhead.tint(c.label2),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CruSpace.s12),
              ],
            ],
          ),
        ),
        const SizedBox(height: CruSpace.cardGap),

        // Footer & Templates policy
        CruCard(
          semanticLabel: 'Footer & template policy',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Footer & templates', style: CruType.headline.tint(c.label)),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Footer note',
                controller: _footerText,
                enabled: canEdit,
                optional: true,
                maxLines: 2,
                help: 'Printed across all documents at the bottom.',
              ),
              const SizedBox(height: CruSpace.s16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Everyone uses clinic templates',
                  style: CruType.body.w500.tint(c.label),
                ),
                subtitle: Text(
                  'Locks team members to templates managed by the clinic',
                  style: CruType.subhead.tint(c.label2),
                ),
                value: _lockTemplates,
                onChanged: canEdit
                    ? (v) => setState(() => _lockTemplates = v)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.s24),

        // Save button
        if (canEdit)
          Align(
            alignment: Alignment.centerRight,
            child: CruButton(
              label: _saving ? 'Saving…' : 'Save clinic details',
              onPressed: _saving ? null : _save,
            ),
          ),
        const SizedBox(height: CruSpace.s32),
      ],
    );
  }
}
