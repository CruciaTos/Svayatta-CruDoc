import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/inventory/data/providers/inventory_view_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Filters live while typing without rebuilding on every keystroke.
const Duration _debounce = Duration(milliseconds: 150);

String _shortcut() =>
    defaultTargetPlatform == TargetPlatform.macOS ? '⌘F' : 'Ctrl F';

/// "Search items, batches or suppliers", 44 px, with the Ctrl F keycap.
class InventorySearchField extends ConsumerStatefulWidget {
  const InventorySearchField({super.key, required this.focusNode});

  /// Focused by Ctrl/⌘ F.
  final FocusNode focusNode;

  @override
  ConsumerState<InventorySearchField> createState() =>
      _InventorySearchFieldState();
}

class _InventorySearchFieldState extends ConsumerState<InventorySearchField> {
  late final TextEditingController _text;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(
      text: ref.read(inventoryControllerProvider).query,
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
      ref.read(inventoryControllerProvider.notifier).setQuery(value);
    });
  }

  void _clear() {
    _timer?.cancel();
    _text.clear();
    setState(() {});
    ref.read(inventoryControllerProvider.notifier).setQuery('');
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    // The query can be cleared from elsewhere ("Clear search").
    ref.listen(inventoryControllerProvider.select((s) => s.query), (_, next) {
      final pending = _timer?.isActive ?? false;
      if (!pending && next != _text.text) {
        _text.text = next;
        setState(() {});
      }
    });

    return Container(
      height: CruSize.searchBar,
      padding: const EdgeInsets.fromLTRB(CruSpace.s14, 0, CruSpace.s10, 0),
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
                  'Search items, batches or suppliers',
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
            CruKeycap(_shortcut()),
        ],
      ),
    );
  }
}
