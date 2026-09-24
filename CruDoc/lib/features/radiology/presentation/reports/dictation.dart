import 'dart:io';

import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

// Dictation. The Scribe feature's recorder sends audio to a cloud model
// that writes consultation notes; the radiology module is local-only and
// needs plain transcription, so CruDoc's own speech-to-text isn't
// connected here yet. The mic says so and points to the voice typing the
// operating system already offers, which types into any field.

/// The mic beside a report field. On: the field takes the cursor and the
/// note under it explains how to dictate today.
class RadDictationButton extends StatelessWidget {
  const RadDictationButton({super.key, required this.active, required this.onPressed});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onPressed,
      semanticLabel: active ? 'Hide dictation' : 'Dictate',
      tooltip: active ? 'Hide dictation' : 'Dictate',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        width: CruSize.rowCapsule,
        height: CruSize.rowCapsule,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: active ? c.inset : (hovered ? c.hoverFill : c.inset.withValues(alpha: 0)),
          shape: const CircleBorder(),
        ),
        child: CruIcon(CruIcons.mic, size: 16, strokeWidth: 1.9, color: active ? c.label : c.label3),
      ),
    );
  }
}

/// Under the field while the mic is on: CruDoc's dictation isn't connected
/// yet, and the system's voice typing works in the field right now.
class RadDictationNote extends StatelessWidget {
  const RadDictationNote({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (String? keys, String? how) = Platform.isWindows
        ? ('Win + H', 'Windows voice typing works here now: the cursor is in this field, press')
        : Platform.isMacOS
            ? ('Fn Fn', 'macOS dictation works here now: the cursor is in this field, press')
            : (null, null);
    return Padding(
      padding: const EdgeInsets.only(top: CruSpace.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const RadNotConnected(
            icon: CruIcons.mic,
            title: 'Dictation not connected yet',
            body: "CruDoc's own speech-to-text turns on once a transcription service is "
                'connected. Nothing is recorded or sent until then.',
          ),
          if (keys != null && how != null) ...[
            const SizedBox(height: CruSpace.s8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: CruSpace.s6,
              runSpacing: CruSpace.s4,
              children: [
                Text(how, style: CruType.caption.tint(c.label2)),
                CruKeycap(keys),
                Text('and speak.', style: CruType.caption.tint(c.label2)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
