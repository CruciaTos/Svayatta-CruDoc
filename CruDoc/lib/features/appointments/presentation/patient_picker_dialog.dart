import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final patientsAsync = ref.watch(filteredPatientsProvider);

    return Dialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s24,
      ),
      shape: cruShape(
        CruRadius.card,
        side: BorderSide(color: c.cardBorder),
      ),
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
                  CruIconTile(
                    icon: CruIcons.search,
                    tone: CruTileTone.neutral,
                  ),
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
                height: CruSize.actionButton,
                padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
                decoration: ShapeDecoration(
                  color: c.inset,
                  shape: cruShape(CruRadius.control),
                ),
                child: Row(
                  children: [
                    CruIcon(CruIcons.search, size: 18, color: c.label3),
                    const SizedBox(width: CruSpace.s10),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        autofocus: true,
                        style: CruType.input.tint(c.label),
                        cursorColor: c.accent,
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                          ref.read(searchQueryProvider.notifier).state = value;
                        },
                        decoration: InputDecoration.collapsed(
                          hintText: 'Search by name, phone, or diagnosis…',
                          hintStyle: CruType.input.tint(c.label3),
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      CruIconButton(
                        icon: CruIcons.close,
                        size: 28,
                        iconSize: 14,
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
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(CruSpace.s24),
                        child: Text(
                          _searchQuery.isEmpty
                              ? 'No patients yet. Create one to get started.'
                              : 'No patients match "$_searchQuery".',
                          textAlign: TextAlign.center,
                          style: CruType.subhead.tint(c.label3),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: patients.length,
                    separatorBuilder: (_, __) => const CruSeparator(
                      indent: 72,
                      endIndent: CruSpace.s20,
                    ),
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
            CruMonogram(
              name: patient.fullName,
              size: CruSize.monogramList,
            ),
            const SizedBox(width: CruSpace.s14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    patient.fullName,
                    style: CruType.body.w600.tint(c.label),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
                          Text(
                            '  ·  ',
                            style: CruType.caption.tint(c.label3),
                          ),
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
