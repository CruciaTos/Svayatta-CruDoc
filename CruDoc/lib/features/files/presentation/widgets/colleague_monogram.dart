import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Up to two initials, ignoring a leading "Dr" / "Dr.".
String colleagueInitials(String name) {
  final words = [
    for (final w in name.trim().split(RegExp(r'\s+')))
      if (w.isNotEmpty && w.toLowerCase() != 'dr' && w.toLowerCase() != 'dr.')
        w,
  ];
  if (words.isEmpty) return '?';
  final first = words.first[0];
  final last = words.length > 1 ? words.last[0] : '';
  return (first + last).toUpperCase();
}

/// The first word of the name after "Dr", for the caption under an avatar.
String colleagueShortName(String name) {
  final words = [
    for (final w in name.trim().split(RegExp(r'\s+')))
      if (w.isNotEmpty && w.toLowerCase() != 'dr' && w.toLowerCase() != 'dr.')
        w,
  ];
  return words.isEmpty ? 'Colleague' : words.first;
}

/// Grey monogram circle.
class ColleagueMonogram extends StatelessWidget {
  const ColleagueMonogram({
    super.key,
    required this.name,
    this.size = CruSize.actionButton,
  });

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: c.inset,
        shape: CircleBorder(side: BorderSide(color: c.hairline)),
      ),
      child: Text(
        colleagueInitials(name),
        style: (size < CruSize.control ? CruType.caption : CruType.callout).w600
            .tint(c.label2),
      ),
    );
  }
}
