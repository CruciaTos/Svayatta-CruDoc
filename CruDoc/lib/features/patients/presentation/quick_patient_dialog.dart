import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/domain/duplicate_patient.dart';
import 'package:doctor_management_app/features/patients/domain/quick_patient.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/patient_dialogs.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

Future<Patient?> showQuickPatientDialog(
  BuildContext context, {
  String initialName = '',
  String initialPhone = '',
  String submitLabel = 'Add patient',
}) {
  return showDialog<Patient?>(
    context: context,
    barrierDismissible: false,
    builder: (_) => QuickPatientDialog(
      initialName: initialName,
      initialPhone: initialPhone,
      submitLabel: submitLabel,
    ),
  );
}

class QuickPatientDialog extends ConsumerStatefulWidget {
  const QuickPatientDialog({
    super.key,
    this.initialName = '',
    this.initialPhone = '',
    this.submitLabel = 'Add patient',
  });

  final String initialName;
  final String initialPhone;
  final String submitLabel;

  @override
  ConsumerState<QuickPatientDialog> createState() => _QuickPatientDialogState();
}

class _QuickPatientDialogState extends ConsumerState<QuickPatientDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;

  bool _dirty = false;
  bool _saving = false;
  bool _submitted = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initialName);
    _phone = TextEditingController(text: widget.initialPhone);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _edited([Object? _]) {
    setState(() {
      _dirty = true;
      _notice = null;
    });
  }

  /// Optional here; a typed number follows the patient form's rule.
  String? _validatePhone(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty || digits.length >= 10
        ? null
        : 'Enter a 10-digit mobile number.';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submitted = true);
    final fieldsOk = _formKey.currentState!.validate();
    if (!fieldsOk) return;

    final name = _name.text.trim();
    final phone = _phone.text.trim();

    if (phone.isNotEmpty) {
      final existing =
          ref.read(patientsStreamProvider).value ?? const <Patient>[];
      final dup = duplicateByPhone(existing, phone);
      if (dup != null) {
        final useExisting = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dContext) => PatientDialog(
            title: '${dup.fullName} already has this number',
            body: Text(
              '${dup.phone} · ${dup.age}',
              style: CruType.text.tabular.tint(dContext.cru.label2),
            ),
            cancelLabel: 'Add anyway',
            confirmLabel: 'Use ${dup.fullName}',
            onConfirm: () => Navigator.of(dContext).pop(true),
          ),
        );
        if (!mounted) return;
        if (useExisting == true) {
          Navigator.of(context).pop(dup);
          return;
        }
      }
    }

    setState(() {
      _saving = true;
      _notice = null;
    });

    try {
      final patient = quickPatient(name, phone: phone);
      final repo = ref.read(patientRepositoryProvider);
      final id = await repo.createPatient(patient);
      final created = await repo.getPatient(id);
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _notice =
            "Couldn't save this patient. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.trim();
    return CruFormDialog(
      title: 'New patient',
      leading: name.isEmpty
          ? const CruIconTile(
              icon: CruIcons.userPlus,
              tone: CruTileTone.neutral,
            )
          : CruMonogram(name: name, size: CruSize.iconTile),
      submitLabel: widget.submitLabel,
      onSubmit: _save,
      busy: _saving,
      dirty: _dirty,
      notice: _notice,
      body: Form(
        key: _formKey,
        autovalidateMode: _submitted
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CruFormSection(
              first: true,
              children: [
                CruTextField(
                  label: 'Name',
                  hint: 'e.g. Maya Patel',
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                  onChanged: _edited,
                ),
                CruTextField(
                  label: 'Phone',
                  optional: true,
                  controller: _phone,
                  icon: CruIcons.phone,
                  hint: '98765 43210',
                  tabular: true,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                    LengthLimitingTextInputFormatter(16),
                  ],
                  validator: _validatePhone,
                  onChanged: _edited,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
