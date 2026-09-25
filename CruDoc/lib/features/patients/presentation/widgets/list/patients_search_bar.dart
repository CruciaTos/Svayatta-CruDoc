import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/patients/data/providers/patients_list_providers.dart';
import 'package:doctor_management_app/features/patients/domain/patients_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Search debounce: filters live while typing without rebuilding the
/// list on every keystroke.
const Duration _debounce = Duration(milliseconds: 150);

/// "Ctrl F" / "⌘F".
String patientsSearchShortcut() =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘F' : 'Ctrl F';

/// The full-width 44 px search field, with the Sort button beside it
/// (hidden in the first-week state).
class PatientsSearchBar extends ConsumerStatefulWidget {
  const PatientsSearchBar({
    super.key,
    required this.focusNode,
    required this.sort,
    this.showSort = true,
  });

  /// Focused by Ctrl/⌘ F.
  final FocusNode focusNode;
  final PatientSort sort;
  final bool showSort;

  @override
  ConsumerState<PatientsSearchBar> createState() => _PatientsSearchBarState();
}

class _PatientsSearchBarState extends ConsumerState<PatientsSearchBar> {
  late final TextEditingController _text;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Restores the query when coming back from Patient details.
    _text = TextEditingController(
      text: ref.read(patientsListControllerProvider).query,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // clear button
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      if (!mounted) return;
      ref.read(patientsListControllerProvider.notifier).setQuery(value);
    });
  }

  void _clear() {
    _timer?.cancel();
    _text.clear();
    setState(() {});
    ref.read(patientsListControllerProvider.notifier).setQuery('');
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    // The query can be cleared from elsewhere ("Clear search").
    ref.listen(patientsListControllerProvider.select((s) => s.query), (
      _,
      next,
    ) {
      final pending = _timer?.isActive ?? false;
      if (!pending && next != _text.text) {
        _text.text = next;
        setState(() {});
      }
    });

    final field = Container(
      height: CruSize.searchBar,
      padding: const EdgeInsets.fromLTRB(
        CruSpace.s14,
        0,
        CruSpace.s10,
        0,
      ),
      decoration: ShapeDecoration(
        color: c.surface,
        shape: cruShape(CruRadius.control, side: BorderSide(color: c.hairline)),
        shadows: c.cardShadow,
      ),
      child: Row(
        children: [
          CruIcon(CruIcons.search, size: 18, strokeWidth: 2, color: c.label3),
          const SizedBox(width: CruSpace.s10),
          Expanded(
            child: TextField(
              controller: _text,
              focusNode: widget.focusNode,
              onChanged: _onChanged,
              style: CruType.input.tint(c.label),
              cursorColor: c.accent,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hint: Text(
                  'Search by name, phone, patient ID or condition',
                  style: CruType.input.tint(c.label3),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                ),
              ),
            ),
          ),
          const SizedBox(width: CruSpace.s10),
          if (_text.text.isNotEmpty)
            CruIconButton(
              icon: CruIcons.close,
              size: CruSize.capsule,
              iconSize: 16,
              semanticLabel: 'Clear search',
              tooltip: 'Clear search',
              onPressed: _clear,
            )
          else
            CruKeycap(patientsSearchShortcut()),
        ],
      ),
    );

    if (!widget.showSort) return field;
    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: CruSpace.s12),
        _SortButton(sort: widget.sort),
      ],
    );
  }
}

/// "Sort  Last visit ⌄" with a small on-token menu of [PatientSort].
class _SortButton extends ConsumerWidget {
  const _SortButton({required this.sort});

  final PatientSort sort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final itemShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(CruRadius.control - CruSpace.s6),
    );
    return MenuAnchor(
      alignmentOffset: const Offset(0, CruSpace.s6),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: WidgetStatePropertyAll(c.surface.withValues(alpha: 0)),
        shadowColor: WidgetStatePropertyAll(c.label.withValues(alpha: 0.18)),
        elevation: WidgetStatePropertyAll(c.isEvening ? 0 : 8),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(CruSpace.s6)),
        shape: WidgetStatePropertyAll(
          RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(CruRadius.control),
            side: BorderSide(color: c.hairline),
          ),
        ),
      ),
      menuChildren: [
        for (final s in PatientSort.values)
          MenuItemButton(
            onPressed: () =>
                ref.read(patientsListControllerProvider.notifier).setSort(s),
            style: ButtonStyle(
              minimumSize: const WidgetStatePropertyAll(
                Size(0, CruSize.control),
              ),
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: CruSpace.s12),
              ),
              shape: WidgetStatePropertyAll(itemShape),
              overlayColor: WidgetStatePropertyAll(
                c.hoverFill.withValues(alpha: 0),
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.hovered) ||
                        states.contains(WidgetState.focused)
                    ? c.hoverFill
                    : c.surface,
              ),
            ),
            trailingIcon: s == sort
                ? CruIcon(
                    CruIcons.check,
                    size: 16,
                    strokeWidth: 2.2,
                    color: c.accentText,
                  )
                : null,
            child: Text(
              s.label,
              style: (s == sort ? CruType.text.w600 : CruType.text.w500).tint(
                c.label,
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => CruPressable(
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        semanticLabel: 'Sort by ${sort.label}',
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.searchBar,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
          decoration: ShapeDecoration(
            color: hovered ? c.hoverFill : c.surface,
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(color: c.hairline),
            ),
            shadows: c.cardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Sort', style: CruType.text.w500.tint(c.label2)),
              const SizedBox(width: CruSpace.s6),
              Text(sort.label, style: CruType.text.w500.tint(c.label)),
              const SizedBox(width: CruSpace.s6),
              CruIcon(
                CruIcons.chevronDown,
                size: 14,
                strokeWidth: 2.2,
                color: c.label2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
