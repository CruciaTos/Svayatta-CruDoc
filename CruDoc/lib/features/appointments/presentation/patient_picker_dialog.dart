import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateController;
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/patients/domain/quick_patient.dart';
import 'package:doctor_management_app/features/patients/presentation/patient_form.dart';
import 'package:doctor_management_app/features/patients/presentation/quick_patient_dialog.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Opens a patient search/picker dialog conforming to Calm Clinical design.
/// Returns the selected patient, or null if dismissed.
Future<Patient?> showPatientPickerDialog(
  BuildContext context, {
  String title = 'Select a patient',
}) async {
  return showDialog<Patient?>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _PatientPickerDialog(title: title),
  );
}

class _PatientPickerDialog extends ConsumerStatefulWidget {
  final String title;

  const _PatientPickerDialog({required this.title});

  @override
  ConsumerState<_PatientPickerDialog> createState() =>
      _PatientPickerDialogState();
}

class _PatientPickerDialogState extends ConsumerState<_PatientPickerDialog> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  // Read now, while mounted: dispose() can't touch ref.
  late final StateController<String> _query;

  @override
  void initState() {
    super.initState();
    _query = ref.read(searchQueryProvider.notifier);
    Future.microtask(() => _query.state = '');
  }

  @override
  void dispose() {
    Future.microtask(() => _query.state = '');
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _quickAdd([String? initialName]) async {
    final name = initialName ?? _searchController.text.trim();
    final p = await showQuickPatientDialog(context, initialName: name);
    if (p != null && mounted) {
      Navigator.of(context).pop<Patient>(p);
    }
  }

  Future<void> _fullAdd() async {
    String? id;
    final ok = await showAddPatientSheet(context, onCreated: (v) => id = v);
    if (ok == true && id != null && mounted) {
      final p = await ref.read(patientRepositoryProvider).getPatient(id!);
      if (p != null && mounted) {
        Navigator.of(context).pop<Patient>(p);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final patientsAsync = ref.watch(filteredPatientsProvider);
    final phone = cruIsPhone(context);

    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s24,
      ),
      shape: cruShape(CruRadius.card, side: BorderSide(color: c.cardBorder)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s20,
                CruSpace.s16,
                CruSpace.s12,
                CruSpace.s16,
              ),
              child: Row(
                children: [
                  CruIconTile(icon: CruIcons.search, tone: CruTileTone.neutral),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: CruType.title2.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  CruIconButton(
                    icon: CruIcons.close,
                    size: CruSize.control,
                    iconSize: 18,
                    semanticLabel: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const CruSeparator(),

            // Search input
            Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s20,
                CruSpace.s14,
                CruSpace.s20,
                CruSpace.s10,
              ),
              child: Container(
                height: phone ? CruSize.searchBarPhone : CruSize.actionButton,
                padding: phone
                    ? const EdgeInsets.fromLTRB(CruSpace.s16, 0, CruSpace.s4, 0)
                    : const EdgeInsets.symmetric(horizontal: CruSpace.s14),
                decoration: ShapeDecoration(
                  color: c.inset,
                  shape: cruShape(CruRadius.control),
                ),
                child: Row(
                  children: [
                    CruIcon(
                      CruIcons.search,
                      size: phone ? CruSize.searchIconPhone : 18,
                      color: c.label3,
                    ),
                    SizedBox(width: phone ? CruSpace.s12 : CruSpace.s10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: (phone ? CruType.body : CruType.input).tint(
                          c.label,
                        ),
                        cursorColor: c.accent,
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                          ref.read(searchQueryProvider.notifier).state = value;
                        },
                        decoration: InputDecoration.collapsed(
                          // The phone's dialog is too narrow for the long one.
                          hintText: phone
                              ? 'Name or phone number'
                              : 'Search by name, phone, or diagnosis…',
                          hintStyle: (phone ? CruType.body : CruType.input)
                              .tint(c.label3),
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      CruIconButton(
                        icon: CruIcons.close,
                        size: phone ? CruSize.searchToolPhone : 28,
                        iconSize: phone ? CruSize.searchClearIconPhone : 14,
                        semanticLabel: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          ref.read(searchQueryProvider.notifier).state = '';
                        },
                      ),
                  ],
                ),
              ),
            ),

            // Patient List
            Expanded(
              child: patientsAsync.when(
                loading: () => Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: c.accent,
                  ),
                ),
                error: (error, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(CruSpace.s20),
                    child: CruFormNotice('Error loading patients: $error'),
                  ),
                ),
                data: (patients) {
                  if (patients.isEmpty) {
                    if (_searchQuery.isNotEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(CruSpace.s24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'No patients match "$_searchQuery".',
                                textAlign: TextAlign.center,
                                style: CruType.subhead.tint(c.label3),
                              ),
                              const SizedBox(height: CruSpace.s16),
                              CruButton(
                                label: 'Add "$_searchQuery" as a new patient',
                                kind: CruButtonKind.inset,
                                onPressed: () => _quickAdd(_searchQuery),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(CruSpace.s24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'No patients yet.',
                              textAlign: TextAlign.center,
                              style: CruType.subhead.tint(c.label3),
                            ),
                            const SizedBox(height: CruSpace.s16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CruButton(
                                  label: 'Quick add',
                                  kind: CruButtonKind.inset,
                                  onPressed: () => _quickAdd(),
                                ),
                                if (!phone) ...[
                                  const SizedBox(width: CruSpace.s10),
                                  CruButton(
                                    label: 'New patient (full details)',
                                    kind: CruButtonKind.inset,
                                    onPressed: _fullAdd,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: patients.length,
                    separatorBuilder: (_, _) =>
                        const CruSeparator(indent: 72, endIndent: CruSpace.s20),
                    itemBuilder: (context, index) {
                      final patient = patients[index];
                      return _PatientListItem(
                        patient: patient,
                        onTap: () =>
                            Navigator.of(context).pop<Patient>(patient),
                      );
                    },
                  );
                },
              ),
            ),
            const CruSeparator(),
            Padding(
              padding: const EdgeInsets.all(CruSpace.s16),
              child: Row(
                children: [
                  CruButton(
                    label: 'Quick add',
                    kind: CruButtonKind.inset,
                    onPressed: () => _quickAdd(),
                  ),
                  if (!phone) ...[
                    const SizedBox(width: CruSpace.s10),
                    CruButton(
                      label: 'New patient (full details)',
                      kind: CruButtonKind.inset,
                      onPressed: _fullAdd,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientListItem extends StatelessWidget {
  final Patient patient;
  final VoidCallback onTap;

  const _PatientListItem({required this.patient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final phone = patient.phone.trim();
    final diagnosis = patient.diagnosisDisplay.trim();
    final createdDate = DateFormat('dd/MM/yyyy').format(patient.createdAt);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s20,
          vertical: CruSpace.s12,
        ),
        child: Row(
          children: [
            CruMonogram(name: patient.fullName, size: CruSize.monogramList),
            const SizedBox(width: CruSpace.s14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          patient.fullName,
                          style: CruType.body.w600.tint(c.label),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (patientDetailsPending(patient)) ...[
                        const SizedBox(width: CruSpace.s8),
                        Text(
                          'Details pending',
                          style: CruType.caption.tint(c.amberText),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: CruSpace.s2),
                  Row(
                    children: [
                      if (phone.isNotEmpty) ...[
                        Text(
                          phone,
                          style: CruType.subhead.tabular.tint(c.label2),
                        ),
                        if (diagnosis.isNotEmpty) ...[
                          Text('  ·  ', style: CruType.caption.tint(c.label3)),
                        ],
                      ],
                      if (diagnosis.isNotEmpty)
                        Expanded(
                          child: Text(
                            diagnosis,
                            style: CruType.subhead.tint(c.label2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Added $createdDate',
                    style: CruType.caption.tint(c.label3),
                  ),
                ],
              ),
            ),
            CruIcon(CruIcons.chevronRight, size: 16, color: c.label3),
          ],
        ),
      ),
    );
  }
}
