import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/settings/presentation/documents/documents_settings_section.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Documents, in the sidebar: templates, the clinic's letterhead details
/// and each doctor's own details and signature, for bills, prescriptions,
/// referral letters, reports and certificates. Pads itself like the other
/// Calm Clinical pages.
class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  /// Wide enough for three template cards side by side.
  static const double _maxWidth = 1080;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final phone = cruIsPhone(context);
    final width = MediaQuery.sizeOf(context).width;
    final padding = phone
        ? CruSpace.mainPaddingPhone
        : width < CruBreakpoint.compact
        ? CruSpace.mainPaddingCompact
        : CruSpace.mainPadding;

    return SingleChildScrollView(
      padding: padding,
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Documents',
                  style:
                      (phone
                              ? CruType.largeTitle.copyWith(fontSize: 28)
                              : CruType.largeTitle)
                          .tint(c.label),
                ),
              ),
              const SizedBox(height: CruSpace.s2),
              Text(
                'Templates, letterhead and signatures for bills, '
                'prescriptions, referrals, reports and certificates.',
                style: CruType.text.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.cardGap),
              const DocumentsSettingsSection(),
            ],
          ),
        ),
      ),
    );
  }
}
