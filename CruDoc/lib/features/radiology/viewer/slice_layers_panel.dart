import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Icons the slice overlay needs that [CruIcons] doesn't have.
abstract final class RadSliceIcons {
  static const lock = CruIconData(
    'M8 10.5V8a4 4 0 0 1 8 0v2.5',
    rects: [(5, 10.5, 14, 10, 2.5)],
  );
  static const unlock = CruIconData(
    'M8 10.5V8a4 4 0 0 1 7.6-1.7',
    rects: [(5, 10.5, 14, 10, 2.5)],
  );
  static const layers = CruIconData(
    'M12 3.5 3.5 8 12 12.5 20.5 8zM3.5 12 12 16.5 20.5 12M3.5 16 12 20.5 '
    '20.5 16',
  );
}

/// One slice of a stack that has marks on it.
@immutable
class RadLayerEntry {
  const RadLayerEntry({
    required this.sliceIndex,
    required this.imageId,
    required this.markCount,
    required this.current,
  });

  /// Position in the stack, from 0.
  final int sliceIndex;
  final String imageId;
  final int markCount;

  /// The slice on screen now.
  final bool current;
}

/// Every slice that has marks, to hop between them (the phone's "layers").
/// Stays open while the doctor jumps; [onClose] shuts it.
class RadSliceLayers extends StatelessWidget {
  const RadSliceLayers({
    super.key,
    required this.entries,
    required this.onJump,
    required this.onClose,
  });

  final List<RadLayerEntry> entries;
  final void Function(String imageId) onJump;
  final VoidCallback onClose;

  static const double _maxWidth = 220;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _maxWidth, maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(CruRadius.card),
          border: Border.all(color: c.separator),
        ),
        child: Padding(
          padding: const EdgeInsets.all(CruSpace.s12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CruIcon(
                    RadSliceIcons.layers,
                    size: 16,
                    strokeWidth: 2,
                    color: c.label2,
                  ),
                  const SizedBox(width: CruSpace.s8),
                  Expanded(
                    child: Text(
                      'Layers',
                      style: CruType.callout.tint(c.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${entries.length}',
                    style: CruType.caption.tabular.tint(c.label2),
                  ),
                  const SizedBox(width: CruSpace.s4),
                  CruIconButton(
                    icon: CruIcons.close,
                    onPressed: onClose,
                    semanticLabel: 'Close layers',
                    size: CruSize.chip,
                    iconSize: 14,
                  ),
                ],
              ),
              const SizedBox(height: CruSpace.s8),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
                  child: Text(
                    'No marked slices yet.',
                    style: CruType.caption.tint(c.label3),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: entries.length,
                    separatorBuilder: (context, i) =>
                        const SizedBox(height: CruSpace.s4),
                    itemBuilder: (context, i) => _Row(
                      entry: entries[i],
                      onTap: () => onJump(entries[i].imageId),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.onTap});

  final RadLayerEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final marks = '${entry.markCount} ${entry.markCount == 1 ? 'mark' : 'marks'}';
    // Inner radius = card radius - inset.
    const radius = CruRadius.card - CruSpace.s12;
    return CruPressable(
      onTap: onTap,
      semanticLabel: 'Slice ${entry.sliceIndex + 1}, $marks',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        padding: const EdgeInsets.symmetric(
          horizontal: CruSpace.s12,
          vertical: CruSpace.s8,
        ),
        decoration: BoxDecoration(
          color: entry.current
              ? c.accentTint
              : hovered
              ? c.hoverFill
              : c.inset,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Slice ${entry.sliceIndex + 1}',
                style: CruType.callout.tabular.tint(
                  entry.current ? c.accentText : c.label,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: CruSpace.s8),
            Text(
              marks,
              style: CruType.caption.tabular.tint(
                entry.current ? c.accentText : c.label2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
