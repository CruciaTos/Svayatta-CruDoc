import 'package:flutter/material.dart';

import 'package:doctor_management_app/core/models/doctor_specialty.dart';

/// The second step after picking a specialty that has sub-specialties
/// (Dentist): "General dentistry" or one of the sub-specialties. Used by
/// the sign-in pill bar, onboarding and the specialty switcher.
class SubspecialtyRow extends StatelessWidget {
  const SubspecialtyRow({
    super.key,
    required this.selected,
    required this.onSelected,
    this.center = false,
  });

  /// The chosen specialty (the parent itself means "General").
  final DoctorSpecialty selected;
  final ValueChanged<DoctorSpecialty> onSelected;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final parent = DoctorSpecialty.ofType(selected.rootType);
    final subs = DoctorSpecialty.subspecialtiesOf(parent.type);
    if (subs.isEmpty) return const SizedBox.shrink();

    Widget chip(DoctorSpecialty spec, String text) {
      final on = selected.type == spec.type;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () => onSelected(spec),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: on ? spec.accentColor : Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: on ? spec.accentColor : const Color(0xFFE2E8F0),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(spec.icon,
                      size: 14, color: on ? Colors.white : spec.accentColor),
                  const SizedBox(width: 6),
                  Text(
                    text,
                    style: TextStyle(
                      color: on ? Colors.white : const Color(0xFF334155),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            center ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Text(
              '${parent.label} specialty',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          chip(parent, 'General'),
          for (final s in subs) chip(s, s.label),
        ],
      ),
    );
  }
}
