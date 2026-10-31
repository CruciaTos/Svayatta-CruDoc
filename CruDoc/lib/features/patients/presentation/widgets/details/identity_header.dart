import 'package:flutter/material.dart';
import 'package:doctor_management_app/features/patients/domain/patients_builder.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_common.dart';
import 'package:doctor_management_app/features/patients/presentation/widgets/details/details_top_bar.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The pinned top of Patient details. First line: the way back, the •••
/// menu and New visit. Then the patient: monogram, name, "age · sex ·
/// phone · Patient since", the allergy pill, Call and WhatsApp. It stays
/// put while Overview and its sub-screens open and close below it.
class PatientDetailsHeader extends StatelessWidget {
  const PatientDetailsHeader({
    super.key,
    required this.summary,
    required this.allergies,
    required this.onBack,
    required this.onCall,
    required this.onWhatsApp,
    required this.menu,
    required this.onNewVisit,
    this.backLabel,
    this.tabs,
    this.actions,
  });

  final PatientSummary summary;

  /// Null when nothing is recorded (the pill is hidden).
  final KnownAllergies? allergies;
  final VoidCallback onBack;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;

  /// The ••• menu.
  final Widget menu;

  /// Null hides New visit (not part of the person's role).
  final VoidCallback? onNewVisit;

  /// The back link's label while a sub-screen is open ("Overview").
  final String? backLabel;

  /// The switch between Overview and Clinical; null when there is only
  /// Overview.
  final Widget? tabs;

  /// Buttons before the ••• menu (Charting and Recall for dentists).
  /// [compact] is true when the line is short of room: icon buttons then.
  final List<Widget> Function(bool compact)? actions;

  /// Below this width the first line's buttons are icon buttons.
  static const double compactBelow = 720;

  /// Below this width the header is the phone one.
  static const double phoneBelow = 600;
  static const double _phoneMonogram = 44;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final p = summary.patient;
    final hasPhone = p.phone.trim().isNotEmpty;
    final a = allergies;
    final Widget? allergyPill = a == null
        ? null
        : a.none
        ? const CruInfoPill(
            text: 'No known allergies',
            icon: CruIcons.check,
            tone: CruInfoPillTone.outlined,
          )
        : CruInfoPill(
            text: 'Allergic to ${a.text}',
            icon: CruIcons.warning,
            tone: CruInfoPillTone.allergy,
          );

    return LayoutBuilder(
      builder: (context, box) {
        final phone = box.maxWidth < phoneBelow;
        final meta = [
          phone ? PatientFormat.ageSex(p) : PatientFormat.ageSexLong(p),
          if (hasPhone) PatientFormat.phone(p.phone),
          if (!phone) 'Patient since ${PatientFormat.longDate(p.createdAt)}',
        ].join(' · ');

        final compact = box.maxWidth < compactBelow;
        final topLine = Row(
          children: [
            // Shrinks rather than overflow when a long back label meets
            // the buttons on a narrow phone.
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: DetailsBackLink(onBack: onBack, label: backLabel),
                ),
              ),
            ),
            for (final a in actions?.call(compact) ?? const <Widget>[]) ...[
              a,
              const SizedBox(width: CruSpace.s10),
            ],
            menu,
            if (onNewVisit != null) ...[
              const SizedBox(width: CruSpace.s10),
              CruButton(
                label: 'New visit',
                icon: CruIcons.plus,
                onPressed: onNewVisit,
              ),
            ],
          ],
        );
        final name = Semantics(
          header: true,
          child: Text(
            p.fullName,
            style: (phone ? CruType.title2 : CruType.title).tint(c.label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
        final metaText = Text(
          meta,
          style: CruType.text.tabular.tint(c.label2),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
        // Phones: icon buttons, so the name keeps its room.
        final contact = !hasPhone
            ? const <Widget>[]
            : phone
            ? [
                const SizedBox(width: CruSpace.s12),
                CruSquareButton(
                  icon: CruIcons.phone,
                  secondary: true,
                  semanticLabel: 'Call ${p.fullName}',
                  tooltip: 'Call',
                  onPressed: onCall,
                ),
                const SizedBox(width: CruSpace.s8),
                CruSquareButton(
                  icon: CruIcons.whatsapp,
                  secondary: true,
                  semanticLabel: 'WhatsApp ${p.fullName}',
                  tooltip: 'WhatsApp',
                  onPressed: onWhatsApp,
                ),
              ]
            : [
                const SizedBox(width: CruSpace.s16),
                CruCapsuleButton(
                  label: 'Call',
                  icon: CruIcons.phone,
                  kind: CruCapsuleKind.tinted,
                  height: CruSize.profileCapsule,
                  large: true,
                  semanticLabel: 'Call ${p.fullName}',
                  onPressed: onCall,
                ),
                const SizedBox(width: CruSpace.s8),
                CruCapsuleButton(
                  label: 'WhatsApp',
                  icon: CruIcons.whatsapp,
                  kind: CruCapsuleKind.tinted,
                  height: CruSize.profileCapsule,
                  large: true,
                  semanticLabel: 'WhatsApp ${p.fullName}',
                  onPressed: onWhatsApp,
                ),
              ];

        if (phone) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              topLine,
              const SizedBox(height: CruSpace.s8),
              Row(
                children: [
                  CruMonogram(name: p.fullName, size: _phoneMonogram),
                  const SizedBox(width: CruSpace.s12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [name, metaText],
                    ),
                  ),
                  ...contact,
                ],
              ),
              if (allergyPill != null) ...[
                const SizedBox(height: CruSpace.s10),
                Align(alignment: Alignment.centerLeft, child: allergyPill),
              ],
              if (tabs != null) ...[
                const SizedBox(height: CruSpace.s12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: tabs,
                  ),
                ),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            topLine,
            const SizedBox(height: CruSpace.s12),
            Row(
              children: [
                CruMonogram(name: p.fullName, size: CruSize.monogramPreview),
                const SizedBox(width: CruSpace.s16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      name,
                      const SizedBox(height: CruSpace.s2),
                      metaText,
                      if (allergyPill != null) ...[
                        const SizedBox(height: CruSpace.s8),
                        allergyPill,
                      ],
                    ],
                  ),
                ),
                ...contact,
              ],
            ),
            if (tabs != null) ...[
              const SizedBox(height: CruSpace.s16),
              Align(alignment: Alignment.centerLeft, child: tabs),
            ],
          ],
        );
      },
    );
  }
}
