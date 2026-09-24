import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What the AI second read checks, in the order it lists them.
const radAiCategories = <({String label, String detail})>[
  (label: 'Tooth numbering', detail: 'An FDI number on every tooth'),
  (label: 'Caries', detail: 'Proximal and occlusal radiolucencies'),
  (label: 'Periapical lesions', detail: 'Radiolucencies at the root apices'),
  (label: 'Bone loss', detail: 'Crestal bone level against the CEJ'),
  (label: 'Restorations, RCT and implants', detail: 'Fillings, crowns, root fillings, fixtures'),
  (label: 'Impacted teeth', detail: 'Unerupted or impacted teeth'),
  (label: 'Missing teeth', detail: 'Gaps in the arch'),
];

// ───────────────────────────── Second read panel ─────────────────────────────

/// AI second read side panel for one 2D image. No AI is connected yet, so
/// it says so plainly, lists what the read will check, and keeps the run
/// button disabled. It never shows findings it doesn't have.
class RadAiSecondReadPanel extends ConsumerWidget {
  const RadAiSecondReadPanel({super.key, required this.study, required this.imageId, this.onClose});

  final RadStudy study;
  final String imageId;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final on = ref.watch(radSettingsProvider).value?.ai('secondRead') ?? false;
    return ListView(
      padding: const EdgeInsets.all(CruSpace.s16),
      children: [
        Row(
          children: [
            const RadAiMark(),
            const SizedBox(width: CruSpace.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI second read', style: CruType.headline.tint(c.label)),
                  Text('A second look at this image', style: CruType.caption.tint(c.label2)),
                ],
              ),
            ),
            if (onClose != null)
              CruIconButton(
                icon: CruIcons.close,
                size: CruSize.squareButton,
                iconSize: 18,
                semanticLabel: 'Close',
                tooltip: 'Close',
                onPressed: onClose,
              ),
          ],
        ),
        const SizedBox(height: CruSpace.s16),
        if (!on)
          const RadNotConnected(
            icon: CruIcons.sparkle,
            title: 'AI second read is off',
            body: 'Turn it on in Radiology settings, under AI.',
          )
        else ...[
          const RadNotConnected(
            title: 'No AI key connected',
            body: 'Once a key is connected, this image is de-identified and checked for '
                'the findings below, for you to confirm or reject. Nothing leaves this '
                'computer until then.',
          ),
          const SizedBox(height: CruSpace.s12),
          const RadAiActionButton(label: 'Run AI second read', expand: true),
          const SizedBox(height: CruSpace.s6),
          Text(
            'Runs once an AI key is connected. The image is de-identified first.',
            style: CruType.caption.tint(c.label3),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: CruSpace.s20, bottom: CruSpace.s4),
          child: Text('What it checks', style: CruType.groupLabel.tint(c.label2)),
        ),
        for (final cat in radAiCategories)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CruSpace.s8),
            child: Row(
              children: [
                Container(
                  width: CruSize.smallDot,
                  height: CruSize.smallDot,
                  decoration: ShapeDecoration(color: c.ai, shape: const CircleBorder()),
                ),
                const SizedBox(width: CruSpace.s10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(cat.label, style: CruType.callout.tint(c.label)),
                      Text(cat.detail, style: CruType.caption.tint(c.label2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ───────────────────────────── Shared AI pieces ─────────────────────────────

/// The violet AI mark: a sparkle on the AI tint.
class RadAiMark extends StatelessWidget {
  const RadAiMark({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      width: CruSize.iconTile,
      height: CruSize.iconTile,
      alignment: Alignment.center,
      decoration: ShapeDecoration(color: c.aiTint, shape: cruShape(CruRadius.iconTile)),
      child: CruIcon(CruIcons.sparkle, size: 18, strokeWidth: 1.8, color: c.ai),
    );
  }
}

/// A violet AI action ("Run AI second read", "AI place landmarks"). With
/// no [onPressed] it shows dimmed: it can't run until a key is connected.
class RadAiActionButton extends StatelessWidget {
  const RadAiActionButton({super.key, required this.label, this.onPressed, this.expand = false});

  final String label;
  final VoidCallback? onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final enabled = onPressed != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: CruPressable(
        onTap: onPressed,
        semanticLabel: enabled ? label : '$label, needs an AI key',
        tooltip: enabled ? null : 'Needs an AI key',
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          height: CruSize.control,
          width: expand ? double.infinity : null,
          padding: const EdgeInsets.symmetric(horizontal: CruSpace.s14),
          decoration: ShapeDecoration(
            color: hovered ? cruHoverShade(c.aiTint, c) : c.aiTint,
            shape: cruShape(CruRadius.control),
          ),
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CruIcon(CruIcons.sparkle, size: 16, strokeWidth: 1.8, color: c.ai),
              const SizedBox(width: CruSpace.s6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: CruType.text.w600.tint(c.ai),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────── Settings switches ─────────────────────────────

const _aiSwitches = <({String key, String title, String detail})>[
  (
    key: 'secondRead',
    title: 'AI second read',
    detail: 'Checks 2D images for caries, periapical lesions, bone loss and more, for you to confirm.'
  ),
  (key: 'cbct', title: 'CBCT AI', detail: 'Segments teeth, the mandibular canal and the airway in CBCT.'),
  (key: 'ceph', title: 'Ceph landmarks', detail: 'Places cephalometric landmarks for you to adjust.'),
  (key: 'draft', title: 'Draft the report', detail: 'Writes a first draft from your findings and measurements.'),
  (
    key: 'differential',
    title: 'Differential diagnosis',
    detail: 'Suggests differentials for a lesion from its description.'
  ),
];

/// On/off switches for every AI feature (RadSettings.aiEnabled keys:
/// secondRead, cbct, ceph, draft, differential). Shown in Settings.
class RadAiSwitches extends ConsumerWidget {
  const RadAiSwitches({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final settings = ref.watch(radSettingsProvider).value;
    if (settings == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const RadNotConnected(
          title: 'No AI key connected',
          body: 'The tools you switch on here run once an AI key is connected. '
              'Images are de-identified before they are sent.',
        ),
        const SizedBox(height: CruSpace.s8),
        for (var i = 0; i < _aiSwitches.length; i++) ...[
          if (i > 0) const CruSeparator(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: CruSpace.s12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_aiSwitches[i].title, style: CruType.callout.tint(c.label)),
                      const SizedBox(height: CruSpace.s2),
                      Text(_aiSwitches[i].detail, style: CruType.caption.tint(c.label2)),
                    ],
                  ),
                ),
                const SizedBox(width: CruSpace.s16),
                _AiToggle(
                  label: _aiSwitches[i].title,
                  value: settings.ai(_aiSwitches[i].key),
                  onChanged: (v) => _set(ref, _aiSwitches[i].key, _aiSwitches[i].title, v),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _set(WidgetRef ref, String key, String title, bool on) async {
    final rad = ref.read(radiologyProvider);
    final s = await ref.read(radSettingsProvider.future);
    await rad.saveSettings(s.copyWith(aiEnabled: {...s.aiEnabled, key: on}));
    await rad.log(on ? 'Turned on AI' : 'Turned off AI', targetKind: 'settings', detail: title);
  }
}

/// A switch in the AI violet.
class _AiToggle extends StatelessWidget {
  const _AiToggle({required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Semantics(
      toggled: value,
      child: CruPressable(
        onTap: () => onChanged(!value),
        semanticLabel: label,
        builder: (context, hovered) => AnimatedContainer(
          duration: CruMotion.of(context, CruMotion.fast),
          curve: CruMotion.curve,
          width: CruSpace.s32 + CruSpace.s8,
          height: CruSpace.s24,
          padding: const EdgeInsets.all(CruSpace.s2),
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          decoration: ShapeDecoration(
            color: value ? c.ai : (hovered ? cruHoverShade(c.track, c) : c.track),
            shape: const StadiumBorder(),
          ),
          child: Container(
            width: CruSpace.s20,
            height: CruSpace.s20,
            decoration: ShapeDecoration(
              color: c.surface,
              shape: const CircleBorder(),
              shadows: c.segmentShadow,
            ),
          ),
        ),
      ),
    );
  }
}
