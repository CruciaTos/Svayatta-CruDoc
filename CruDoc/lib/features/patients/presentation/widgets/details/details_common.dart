import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A card heading: title (17/600) with an optional trailing widget
/// ("2 notes", "See all", "Edit") on the same baseline.
class DetailsCardHeader extends StatelessWidget {
  const DetailsCardHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: CruType.headline.tint(c.label)),
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: CruSpace.s12),
          trailing!,
        ],
      ],
    );
  }
}

/// "Upcoming" / "Past" (12/600 label2).
class DetailsSectionLabel extends StatelessWidget {
  const DetailsSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Text(text, style: CruType.groupLabel.tint(context.cru.label2)),
      );
}

/// What a free-text allergy field says, if anything.
class KnownAllergies {
  const KnownAllergies._(this.none, this.text);

  /// Recorded as none ("None", "Nil", "NKDA", ...).
  final bool none;

  /// The recorded allergies (empty when [none]).
  final String text;

  static const _negatives = {
    'none',
    'nil',
    'no',
    'nkda',
    'nka',
    'n/a',
    'na',
    '-',
    '--',
    'no known',
    'none known',
    'no known allergies',
    'no known allergy',
    'no allergies',
    'no allergy',
    'not known',
  };

  /// Null when nothing was recorded: the allergy chip stays hidden
  /// rather than claiming "No known allergies" nobody checked.
  static KnownAllergies? parse(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    final key = text.toLowerCase().replaceAll(RegExp(r'[.\s]+$'), '').trim();
    if (_negatives.contains(key) || key.startsWith('no known')) {
      return const KnownAllergies._(true, '');
    }
    return KnownAllergies._(false, text);
  }
}
