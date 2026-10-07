import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/team/data/team_providers.dart';
import 'package:doctor_management_app/features/team/presentation/team_widgets.dart';

/// Which of the [available] features (module keys) a person uses.
/// [selected] null means all of them; [onChanged] reports null again when
/// everything is ticked, so the person has no personal limit.
class FeaturesChecklist extends StatelessWidget {
  const FeaturesChecklist({
    super.key,
    required this.available,
    required this.selected,
    required this.onChanged,
  });

  final List<String> available;
  final Set<String>? selected;
  final ValueChanged<Set<String>?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ticked = selected ?? available.toSet();
    return CheckListCard(
      items: [
        for (final key in available)
          CheckItem(
            label: kTeamModuleLabels[key] ?? key,
            checked: ticked.contains(key),
            onToggle: () {
              final next = {...ticked.where(available.contains)};
              if (!next.remove(key)) next.add(key);
              onChanged(next.length == available.length ? null : next);
            },
          ),
      ],
    );
  }
}
