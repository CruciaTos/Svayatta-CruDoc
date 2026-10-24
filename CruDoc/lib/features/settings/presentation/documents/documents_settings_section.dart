import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/clinic/clinic_models.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/pdf/data/doc_repository.dart';
import 'package:doctor_management_app/features/settings/presentation/documents/clinic_details_tab.dart';
import 'package:doctor_management_app/features/settings/presentation/documents/my_details_tab.dart';
import 'package:doctor_management_app/features/settings/presentation/documents/templates_tab.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The Documents page's three tabs: Templates · Clinic · My details.
/// Tab numbers are kept in [documentsTabProvider] (0 clinic, 1 my details,
/// 2 templates) so a preview's "Fix" can open the right one.
class DocumentsSettingsSection extends ConsumerWidget {
  const DocumentsSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(clinicAccessProvider).value;
    // Staff have no details or signature of their own.
    final isDoctor = access == null || access.kind == MemberKind.doctor;
    var tab = ref.watch(documentsTabProvider);
    if (tab == 1 && !isDoctor) tab = 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: CruSegmentedControl<int>(
            semanticLabel: 'Documents sections',
            segments: [
              const CruSegment(2, 'Templates'),
              const CruSegment(0, 'Clinic'),
              if (isDoctor) const CruSegment(1, 'My details'),
            ],
            selected: tab,
            onChanged: (v) => ref.read(documentsTabProvider.notifier).state = v,
          ),
        ),
        const SizedBox(height: CruSpace.cardGap),
        switch (tab) {
          1 => const MyDetailsTab(),
          2 => const TemplatesTab(),
          _ => const ClinicDetailsTab(),
        },
      ],
    );
  }
}
