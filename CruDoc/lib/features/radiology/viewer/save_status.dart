import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Where the doctor's work on the open study stands.
enum RadSaveState {
  /// Nothing to report yet (the study has just opened).
  none,

  /// An edit is waiting to be written, or being written.
  saving,

  /// Written to this device; waiting to reach the cloud (offline, or the
  /// upload hasn't run yet).
  savedHere,

  /// In the cloud: other devices will get it.
  synced,

  /// The last save failed; it is tried again shortly.
  failed,
}

/// A small line in the viewer's top bar: "Saving…", "Saved on this
/// device", "Synced" or "Not saved". On a phone only the icon shows.
class RadSaveStatus extends StatelessWidget {
  const RadSaveStatus({super.key, required this.state, this.compact = false});

  final ValueListenable<RadSaveState> state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return ValueListenableBuilder<RadSaveState>(
      valueListenable: state,
      builder: (context, s, _) {
        final (IconData? icon, String text, Color color) = switch (s) {
          RadSaveState.none => (null, '', c.label3),
          RadSaveState.saving => (Icons.sync, 'Saving…', c.label2),
          RadSaveState.savedHere => (
            Icons.cloud_upload_outlined,
            'Saved on this device',
            c.label2,
          ),
          RadSaveState.synced => (Icons.cloud_done_outlined, 'Synced', c.label2),
          RadSaveState.failed => (Icons.error_outline, 'Not saved', c.redText),
        };
        if (icon == null) return const SizedBox.shrink();
        final tip = switch (s) {
          RadSaveState.savedHere =>
            'Saved on this device. It goes to the cloud when there is a connection.',
          RadSaveState.synced => 'Saved and synced to your other devices.',
          RadSaveState.failed => "Couldn't save. Trying again shortly.",
          _ => text,
        };
        return Tooltip(
          message: tip,
          child: Semantics(
            label: text,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: color),
                if (!compact) ...[
                  const SizedBox(width: CruSpace.s4),
                  Text(text, style: CruType.caption.tint(color)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
