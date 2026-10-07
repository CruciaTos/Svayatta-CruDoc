import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/errors/queue_exceptions.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/queue/data/model/queue_entry_model.dart';
import 'package:doctor_management_app/features/queue/data/provider/queue_providers.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:doctor_management_app/core/clinic/clinic_doctors_provider.dart';
import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Modal dialog for checking a patient into today's walk-in queue.
/// Fully themed to Calm Clinical tokens (Day & Evening modes).
class CheckInDialog extends ConsumerStatefulWidget {
  const CheckInDialog({super.key});

  static Future<QueueEntry?> show(BuildContext context) {
    return showDialog<QueueEntry>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const CheckInDialog(),
    );
  }

  @override
  ConsumerState<CheckInDialog> createState() => _CheckInDialogState();
}

class _CheckInDialogState extends ConsumerState<CheckInDialog> {
  bool _isRegistered = true;
  Patient? _selectedPatient;
  String? _attendingDoctorUid;
  final TextEditingController _walkInNameController = TextEditingController();
  final TextEditingController _walkInPhoneController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  QueuePriority _priority = QueuePriority.normal;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _walkInNameController.dispose();
    _walkInPhoneController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submitCheckIn() async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      final repo = ref.read(queueRepositoryProvider);
      QueueEntry created;

      if (_isRegistered) {
        if (_selectedPatient == null) {
          throw const QueueValidationException(
            'Please select a registered patient from the list.',
          );
        }
        created = await repo.checkIn(
          patientId: _selectedPatient!.id,
          reason: _reasonController.text.trim(),
          priority: _priority,
          attendingDoctorUid: _attendingDoctorUid,
        );
      } else {
        final walkInName = _walkInNameController.text.trim();
        if (walkInName.isEmpty) {
          throw const QueueValidationException(
            'Please enter the walk-in patient\'s name.',
          );
        }
        created = await repo.checkIn(
          walkInName: walkInName,
          walkInPhone: _walkInPhoneController.text.trim(),
          reason: _reasonController.text.trim(),
          priority: _priority,
          attendingDoctorUid: _attendingDoctorUid,
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(created);
    } on QueueException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to check in: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final patientsAsync = ref.watch(patientsStreamProvider);
    final allPatients = patientsAsync.value ?? const <Patient>[];

    final doctorsAsync = ref.watch(clinicDoctorsProvider);
    final doctors = doctorsAsync.value ?? const [];
    if (doctors.length > 1 && _attendingDoctorUid == null) {
      final currentAuthUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final isDoctor = ClinicSession.instance.access?.kind == MemberKind.doctor;
      _attendingDoctorUid = (isDoctor && doctors.any((d) => d.uid == currentAuthUid))
          ? currentAuthUid
          : doctors.first.uid;
    }

    return Dialog(
      shape: cruShape(
        CruRadius.card,
        side: BorderSide(color: c.cardBorder),
      ),
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s16,
        vertical: CruSpace.s24,
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CruSpace.s24,
                  CruSpace.s20,
                  CruSpace.s16,
                  CruSpace.s16,
                ),
                child: Row(
                  children: [
                    CruIconTile(
                      icon: CruIcons.userCheck,
                      tone: CruTileTone.accent,
                    ),
                    const SizedBox(width: CruSpace.s12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Check In Patient',
                            style: CruType.title2.tint(c.label),
                          ),
                          const SizedBox(height: CruSpace.s2),
                          Text(
                            'Assign next walk-in token number',
                            style: CruType.subhead.tint(c.label2),
                          ),
                        ],
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

              // Body content
              Padding(
                padding: const EdgeInsets.all(CruSpace.s24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Segmented toggle: Registered Patient vs Walk-in Guest
                    Container(
                      height: CruSize.segmentHeight + 6,
                      padding: const EdgeInsets.all(3),
                      decoration: ShapeDecoration(
                        color: c.inset,
                        shape: cruShape(CruRadius.segmentOuter),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _TypeToggleItem(
                              label: 'Registered Patient',
                              icon: CruIcons.user,
                              isSelected: _isRegistered,
                              onTap: () => setState(() {
                                _isRegistered = true;
                                _errorMessage = null;
                              }),
                            ),
                          ),
                          const SizedBox(width: CruSpace.s4),
                          Expanded(
                            child: _TypeToggleItem(
                              label: 'Walk-in Guest',
                              icon: CruIcons.userPlus,
                              isSelected: !_isRegistered,
                              onTap: () => setState(() {
                                _isRegistered = false;
                                _errorMessage = null;
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: CruSpace.s20),

                    // Registered Patient Selection
                    if (_isRegistered) ...[
                      Text(
                        'Select Patient',
                        style: CruType.subhead.w500.tint(c.label2),
                      ),
                      const SizedBox(height: CruSpace.s6),
                      Autocomplete<Patient>(
                        displayStringForOption: (p) =>
                            '${p.fullName} (${p.phone})',
                        optionsBuilder: (textEditingValue) {
                          final query =
                              textEditingValue.text.trim().toLowerCase();
                          if (query.isEmpty) {
                            return const Iterable<Patient>.empty();
                          }
                          return allPatients.where((p) {
                            if (p.isArchived) return false;
                            final name = p.fullName.toLowerCase();
                            final phone = p.phone.toLowerCase();
                            return name.contains(query) ||
                                phone.contains(query);
                          });
                        },
                        onSelected: (patient) {
                          setState(() {
                            _selectedPatient = patient;
                            _errorMessage = null;
                          });
                        },
                        optionsViewBuilder: (context, onSelected, options) {
                          return Align(
                            alignment: Alignment.topLeft,
                            child: Material(
                              elevation: 4,
                              color: c.surface,
                              shape: cruShape(
                                CruRadius.card,
                                side: BorderSide(color: c.cardBorder),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 240,
                                  maxWidth: 450,
                                ),
                                child: ListView.separated(
                                  padding: EdgeInsets.zero,
                                  shrinkWrap: true,
                                  itemCount: options.length,
                                  separatorBuilder: (_, __) =>
                                      const CruSeparator(),
                                  itemBuilder: (context, i) {
                                    final patient = options.elementAt(i);
                                    return InkWell(
                                      onTap: () => onSelected(patient),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: CruSpace.s14,
                                          vertical: CruSpace.s10,
                                        ),
                                        child: Row(
                                          children: [
                                            CruMonogram(
                                              name: patient.fullName,
                                              size: 32,
                                            ),
                                            const SizedBox(
                                              width: CruSpace.s10,
                                            ),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    patient.fullName,
                                                    style: CruType.body.w600
                                                        .tint(c.label),
                                                  ),
                                                  Text(
                                                    '${patient.gender} · ${patient.phone}',
                                                    style: CruType.caption
                                                        .tint(c.label2),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                        fieldViewBuilder:
                            (context, controller, focusNode, onFieldSubmitted) {
                          return AnimatedContainer(
                            duration: CruMotion.of(context, CruMotion.fast),
                            curve: CruMotion.curve,
                            constraints: const BoxConstraints(
                              minHeight: CruSize.actionButton,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: CruSpace.s14,
                            ),
                            decoration: ShapeDecoration(
                              color: focusNode.hasFocus ? c.surface : c.inset,
                              shape: cruShape(
                                CruRadius.control,
                                side: BorderSide(
                                  color: focusNode.hasFocus
                                      ? c.accent
                                      : c.inset.withValues(alpha: 0),
                                  width: 1.5,
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                CruIcon(
                                  CruIcons.search,
                                  size: 18,
                                  color: c.label3,
                                ),
                                const SizedBox(width: CruSpace.s10),
                                Expanded(
                                  child: TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    style: CruType.input.tint(c.label),
                                    cursorColor: c.accent,
                                    decoration: InputDecoration.collapsed(
                                      hintText: 'Search by name or phone...',
                                      hintStyle: CruType.input.tint(c.label3),
                                    ),
                                    onSubmitted: (_) => onFieldSubmitted(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      if (_selectedPatient != null) ...[
                        const SizedBox(height: CruSpace.s10),
                        Container(
                          padding: const EdgeInsets.all(CruSpace.s12),
                          decoration: ShapeDecoration(
                            color: c.accentWash,
                            shape: cruShape(
                              CruRadius.control,
                              side: BorderSide(color: c.accentTint),
                            ),
                          ),
                          child: Row(
                            children: [
                              CruMonogram(
                                name: _selectedPatient!.fullName,
                                size: CruSize.monogramRow,
                              ),
                              const SizedBox(width: CruSpace.s12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedPatient!.fullName,
                                      style: CruType.body.w600.tint(c.label),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${_selectedPatient!.gender} · ${_selectedPatient!.phone}',
                                      style: CruType.caption.tint(c.label2),
                                    ),
                                  ],
                                ),
                              ),
                              CruIconButton(
                                icon: CruIcons.close,
                                size: 28,
                                iconSize: 14,
                                semanticLabel: 'Remove selection',
                                onPressed: () => setState(
                                  () => _selectedPatient = null,
                                ),
                                tooltip: 'Remove selection',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ] else ...[
                      CruTextField(
                        label: 'Patient Name *',
                        controller: _walkInNameController,
                        hint: 'e.g. Rahul Sharma',
                        icon: CruIcons.user,
                      ),
                      const SizedBox(height: CruSpace.s14),
                      CruTextField(
                        label: 'Phone Number',
                        optional: true,
                        controller: _walkInPhoneController,
                        hint: 'e.g. +91 98765 43210',
                        keyboardType: TextInputType.phone,
                        icon: CruIcons.phone,
                      ),
                    ],

                    const SizedBox(height: CruSpace.s14),

                    CruTextField(
                      label: 'Reason for Visit / Chief Complaint',
                      optional: true,
                      controller: _reasonController,
                      hint:
                          'e.g. High fever, Dressing change, Routine followup...',
                      icon: CruIcons.fileText,
                      maxLines: 2,
                    ),

                    if (doctors.length > 1) ...[
                      const SizedBox(height: CruSpace.s14),
                      CruDropdownField<String>(
                        label: 'Doctor',
                        icon: CruIcons.user,
                        value: _attendingDoctorUid,
                        items: [for (final d in doctors) d.uid],
                        itemLabel: (uid) => doctors
                            .firstWhere((d) => d.uid == uid, orElse: () => doctors.first)
                            .name,
                        onChanged: (v) => setState(() => _attendingDoctorUid = v),
                      ),
                    ],

                    const SizedBox(height: CruSpace.s16),

                    Text(
                      'Queue Priority',
                      style: CruType.subhead.w500.tint(c.label2),
                    ),
                    const SizedBox(height: CruSpace.s8),
                    Row(
                      children: [
                        Expanded(
                          child: _PriorityOptionCard(
                            title: 'Normal',
                            subtitle: 'Standard queue line',
                            icon: CruIcons.check,
                            isSelected: _priority == QueuePriority.normal,
                            isUrgent: false,
                            onTap: () => setState(
                              () => _priority = QueuePriority.normal,
                            ),
                          ),
                        ),
                        const SizedBox(width: CruSpace.s10),
                        Expanded(
                          child: _PriorityOptionCard(
                            title: 'Urgent',
                            subtitle: 'Jumps ahead in line',
                            icon: CruIcons.warning,
                            isSelected: _priority == QueuePriority.urgent,
                            isUrgent: true,
                            onTap: () => setState(
                              () => _priority = QueuePriority.urgent,
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (_errorMessage != null) ...[
                      const SizedBox(height: CruSpace.s16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CruSpace.s12,
                          vertical: CruSpace.s10,
                        ),
                        decoration: ShapeDecoration(
                          color: c.amberTint,
                          shape: cruShape(CruRadius.control),
                        ),
                        child: Row(
                          children: [
                            CruIcon(
                              CruIcons.warning,
                              size: 16,
                              color: c.amberText,
                            ),
                            const SizedBox(width: CruSpace.s8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style:
                                    CruType.caption.w500.tint(c.amberText),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const CruSeparator(),

              // Footer
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CruSpace.s24,
                  vertical: CruSpace.s16,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CruButton(
                      label: 'Cancel',
                      kind: CruButtonKind.secondary,
                      onPressed:
                          _isLoading ? null : () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: CruSpace.s10),
                    CruButton(
                      label: _isLoading ? 'Issuing…' : 'Issue Token',
                      kind: CruButtonKind.primary,
                      onPressed: _isLoading ? null : _submitCheckIn,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeToggleItem extends StatelessWidget {
  final String label;
  final CruIconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeToggleItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: label,
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: isSelected
              ? c.segmentSelected
              : c.segmentSelected.withValues(alpha: 0),
          shape: cruShape(CruRadius.segmentInner),
          shadows: isSelected ? c.segmentShadow : const [],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CruIcon(
              icon,
              size: 16,
              color: isSelected ? c.label : c.label2,
            ),
            const SizedBox(width: CruSpace.s6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CruType.caption.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected || hovered ? c.label : c.label2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final CruIconData icon;
  final bool isSelected;
  final bool isUrgent;
  final VoidCallback onTap;

  const _PriorityOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.isUrgent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final primaryColor = isUrgent ? c.amber : c.accent;
    final primaryText = isUrgent
        ? c.amberText
        : (c.isEvening ? c.accentText : c.accent);
    final selectedBg = isUrgent ? c.amberTint : c.accentWash;

    return CruPressable(
      onTap: onTap,
      scaleOnPress: false,
      semanticLabel: '$title priority, $subtitle',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s12,
          vertical: CruSpace.s12,
        ),
        decoration: ShapeDecoration(
          color: isSelected ? selectedBg : (hovered ? c.surface : c.inset),
          shape: cruShape(
            CruRadius.control,
            side: BorderSide(
              color: isSelected ? primaryColor : c.cardBorder,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
        ),
        child: Row(
          children: [
            CruIcon(
              icon,
              size: 18,
              color: isSelected ? primaryText : c.label3,
            ),
            const SizedBox(width: CruSpace.s10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: CruType.body.w600.tint(
                      isSelected ? primaryText : c.label,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: CruType.caption.tint(
                      isSelected
                          ? (isUrgent ? c.amberText : c.label2)
                          : c.label3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
