import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/morph_tag.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// A card heading: title (17/600) with an optional trailing widget
/// ("2 notes", "See all", "Edit") on the same baseline.
class DetailsCardHeader extends StatelessWidget {
  const DetailsCardHeader({
    super.key,
    required this.title,
    this.trailing,
    this.onTap,
    this.morphId,
  });

  final String title;
  final Widget? trailing;

  /// Opens the card's own screen: the title gets a chevron and is
  /// pressable.
  final VoidCallback? onTap;

  /// Tags the title so it moves into a sub-screen's title (see
  /// [MorphTag]).
  final String? morphId;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final tap = onTap;
    final heading = Semantics(
      header: true,
      child: morphId == null
          ? Text(title, style: CruType.headline.tint(c.label))
          : MorphTag.text(
              id: morphId!,
              text: title,
              style: CruType.headline.tint(c.label),
            ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: tap == null
              ? heading
              : Align(
                  alignment: Alignment.centerLeft,
                  child: CruPressable(
                    onTap: tap,
                    scaleOnPress: false,
                    semanticLabel: 'Open $title',
                    builder: (context, hovered) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        heading,
                        const SizedBox(width: CruSpace.s4),
                        CruIcon(
                          CruIcons.chevronRight,
                          size: 18,
                          strokeWidth: 2,
                          color: hovered ? c.label : c.label3,
                        ),
                      ],
                    ),
                  ),
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

/// Cards stacked with the card gap. Nulls are left out, so an empty slot
/// leaves no gap.
class DetailsStack extends StatelessWidget {
  const DetailsStack(this.children, {super.key});
  final List<Widget?> children;

  @override
  Widget build(BuildContext context) {
    final shown = children.whereType<Widget>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(height: CruSpace.cardGap),
          shown[i],
        ],
      ],
    );
  }
}

/// Two columns when [wide]: [left] flexible, [right] the standard right
/// column. Otherwise one stack, in [narrow] order (left, then right, when
/// not given). A side with nothing in it gives the other the full width.
class DetailsColumns extends StatelessWidget {
  const DetailsColumns({
    super.key,
    required this.wide,
    required this.left,
    required this.right,
    this.narrow,
  });

  final bool wide;
  final List<Widget?> left;
  final List<Widget?> right;
  final List<Widget?>? narrow;

  @override
  Widget build(BuildContext context) {
    final hasLeft = left.any((w) => w != null);
    final hasRight = right.any((w) => w != null);
    if (!wide || !hasLeft || !hasRight) {
      return DetailsStack(narrow ?? [...left, ...right]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: DetailsStack(left)),
        const SizedBox(width: CruSpace.cardGap),
        SizedBox(width: CruSize.rightColumn, child: DetailsStack(right)),
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
