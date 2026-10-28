import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:doctor_management_app/features/settings/presentation/documents/documents_kit.dart';
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
        if (!canEdit) ...[
          const DocNotice('Only clinic admins can change these details.'),
          const SizedBox(height: CruSpace.s16),
        ],

        // Letterhead
        CruCard(
          semanticLabel: 'Clinic details',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DocCardHeader(
                title: 'Clinic details',
                description: 'Printed in the letterhead of every document.',
              ),
              const SizedBox(height: CruSpace.s20),
              DocFieldPair(
                first: CruTextField(
                  label: 'Clinic name',
                  controller: _name,
                  enabled: canEdit,
                  textCapitalization: TextCapitalization.words,
                ),
                second: CruTextField(
                  label: 'Tagline',
                  controller: _tagline,
                  enabled: canEdit,
                  optional: true,
                  hint: 'A short line under the name',
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Address',
                controller: _address,
                enabled: canEdit,
                maxLines: 3,
                hint: 'Street, area, city and PIN code',
                help: 'Up to 3 lines.',
              ),
              const SizedBox(height: CruSpace.s16),
              DocFieldPair(
                first: CruTextField(
                  label: 'Phone',
                  controller: _phone,
                  enabled: canEdit,
                  tabular: true,
                  keyboardType: TextInputType.phone,
                ),
                second: CruTextField(
                  label: 'Email',
                  controller: _email,
                  enabled: canEdit,
                  keyboardType: TextInputType.emailAddress,
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              DocFieldPair(
                first: CruTextField(
                  label: 'Website',
                  controller: _website,
                  enabled: canEdit,
                  optional: true,
                  keyboardType: TextInputType.url,
                ),
                second: CruTextField(
                  label: 'Registration number',
                  controller: _regNo,
                  enabled: canEdit,
                  optional: true,
                  tabular: true,
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Clinic timings',
                controller: _timings,
                enabled: canEdit,
                optional: true,
                maxLines: 2,
                hint: 'e.g. Mon–Sat 9 AM – 8 PM',
                help: 'Up to 2 lines.',
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
              const DocCardHeader(
                title: 'Logo & clinic stamp',
                description: 'PNGs with a transparent background look best.',
              ),
              const SizedBox(height: CruSpace.s20),
              DocSplit(
                first: DocImageSlot(
                  title: 'Clinic logo',
                  caption: 'At the top of the letterhead.',
                  bytes: _logoBytes,
                  emptyIcon: DocIcons.image,
                  actions: [
                    if (canEdit)
                      CruButton(
                        label: _logoBytes == null ? 'Upload' : 'Replace',
                        kind: CruButtonKind.inset,
                        onPressed: _uploadLogo,
                      ),
                  ],
                  onRemove: canEdit
                      ? () => setState(() {
                          _logoPath = '';
                          _logoSha = '';
                          _logoBytes = null;
                        })
                      : null,
                ),
                second: DocImageSlot(
                  title: 'Clinic stamp',
                  caption: 'Where a template places the clinic\'s stamp.',
                  bytes: _stampBytes,
                  emptyIcon: DocIcons.stamp,
                  actions: [
                    if (canEdit)
                      CruButton(
                        label: _stampBytes == null ? 'Upload' : 'Replace',
                        kind: CruButtonKind.inset,
                        onPressed: _uploadStamp,
                      ),
                  ],
                  onRemove: canEdit
                      ? () => setState(() {
                          _stampPath = '';
                          _stampSha = '';
                          _stampBytes = null;
                        })
                      : null,
                ),
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
              const DocCardHeader(title: 'Bills & payments'),
              const SizedBox(height: CruSpace.s16),
              DocToggleRow(
                title: 'Charge GST on bills',
                subtitle: 'Tax invoices split it into CGST and SGST.',
                value: _gstEnabled,
                onChanged: canEdit
                    ? (v) => setState(() => _gstEnabled = v)
                    : null,
              ),
              if (_gstEnabled) ...[
                const SizedBox(height: CruSpace.s16),
                DocFieldPair(
                  first: CruTextField(
                    label: 'GSTIN',
                    controller: _gstin,
                    enabled: canEdit,
                    tabular: true,
                    textCapitalization: TextCapitalization.characters,
                    help: '15 characters.',
                  ),
                ),
              ],
              const SizedBox(height: CruSpace.s16),
              DocToggleRow(
                title: 'Round off to the nearest rupee',
                subtitle: 'Bill totals have no paise.',
                value: _roundOff,
                onChanged: canEdit
                    ? (v) => setState(() => _roundOff = v)
                    : null,
              ),
              const SizedBox(height: CruSpace.s16),
              const CruSeparator(),
              const SizedBox(height: CruSpace.s16),
              DocFieldPair(
                first: CruTextField(
                  label: 'UPI ID',
                  controller: _upiId,
                  enabled: canEdit,
                  optional: true,
                  keyboardType: TextInputType.emailAddress,
                  hint: 'name@bank',
                  help: 'Used for the UPI QR code on bills.',
                ),
                second: CruTextField(
                  label: 'Name shown when paying',
                  controller: _upiName,
                  enabled: canEdit,
                  optional: true,
                ),
              ),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Terms on bills',
                controller: _termsText,
                enabled: canEdit,
                optional: true,
                maxLines: 3,
                help: 'Printed at the bottom of every bill. One per line.',
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
              const DocCardHeader(
                title: 'Document numbering',
                description:
                    'Each kind has its own prefix. Numbers start again every '
                    'financial year (April to March).',
              ),
              const SizedBox(height: CruSpace.s20),
              DocFieldGrid(
                minColumnWidth: 280,
                children: [
                  for (final k in DocKind.values)
                    ListenableBuilder(
                      listenable: _prefixCtrls[k]!,
                      builder: (context, _) =>
                          _prefixField(k, fy: fy, canEdit: canEdit),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.cardGap),

        // Footer & template policy
        CruCard(
          semanticLabel: 'Footer and template policy',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DocCardHeader(title: 'Footer & team templates'),
              const SizedBox(height: CruSpace.s16),
              CruTextField(
                label: 'Footer note',
                controller: _footerText,
                enabled: canEdit,
                optional: true,
                maxLines: 2,
                help: 'Printed at the bottom of every document.',
              ),
              const SizedBox(height: CruSpace.s20),
              DocToggleRow(
                title: 'Everyone uses clinic templates',
                subtitle: 'Team members can\'t pick templates of their own.',
                value: _lockTemplates,
                onChanged: canEdit
                    ? (v) => setState(() => _lockTemplates = v)
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: CruSpace.s24),

        if (canEdit)
          DocSaveBar(
            label: 'Save clinic details',
            saving: _saving,
            onSave: _save,
          ),
        const SizedBox(height: CruSpace.s32),
      ],
    );
  }

  /// One kind's prefix, with the number the next one will get.
  Widget _prefixField(DocKind k, {required String fy, required bool canEdit}) {
    final c = context.cru;
    final typed = _prefixCtrls[k]!.text.trim().toUpperCase();
    final p = typed.isEmpty ? k.defaultPrefix : typed;
    return CruTextField(
      label: k.label,
      controller: _prefixCtrls[k]!,
      enabled: canEdit,
      tabular: true,
      hint: k.defaultPrefix,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
        LengthLimitingTextInputFormatter(5),
      ],
      trailing: Semantics(
        label: 'Next number $p-$fy/0001',
        child: ExcludeSemantics(
          child: Text(
            'Next $p-$fy/0001',
            style: CruType.caption.tabular.tint(c.label3),
          ),
        ),
      ),
    );
  }
}
