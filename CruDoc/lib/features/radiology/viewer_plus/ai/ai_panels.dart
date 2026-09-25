import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:doctor_management_app/core/services/gemini_json_client.dart';
import 'package:doctor_management_app/features/dental/domain/tooth_numbering.dart';
import 'package:doctor_management_app/features/radiology/ai/rad_ai.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_models.dart';
import 'package:doctor_management_app/features/radiology/data/radiology_providers.dart';
import 'package:doctor_management_app/features/radiology/presentation/radiology_ui.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_export.dart';
import 'package:doctor_management_app/features/radiology/viewer/viewer_pane.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// What the AI second read checks, in the order it lists them.
const radAiCategories = <({String label, String detail})>[
  (label: 'Caries', detail: 'Proximal and occlusal radiolucencies'),
  (label: 'Bone loss', detail: 'Crestal bone level against the CEJ'),
  (label: 'Periapical lesions', detail: 'Radiolucencies at the root apices'),
  (label: 'Impacted teeth', detail: 'Unerupted, ectopic or angulated teeth'),
];

// ───────────────────────────── Second read panel ─────────────────────────────

/// AI second read side panel for one 2D image.
/// Supports running the second read, accepting/rejecting/editing findings,
/// and toggling the overlay marks on the image.
class RadAiSecondReadPanel extends ConsumerStatefulWidget {
  const RadAiSecondReadPanel({
    super.key,
    required this.study,
    required this.imageId,
    this.pane,
    this.onClose,
  });

  final RadStudy study;
  final String imageId;
  final RadPane? pane;
  final VoidCallback? onClose;

  @override
  ConsumerState<RadAiSecondReadPanel> createState() => _RadAiSecondReadPanelState();
}

class _RadAiSecondReadPanelState extends ConsumerState<RadAiSecondReadPanel> {
  bool _running = false;
  String? _error;

  Map<String, dynamic>? _latestRun() {
    for (final run in widget.study.aiReads.reversed) {
      if (run['imageId'] == widget.imageId) {
        return run;
      }
    }
    return null;
  }

  List<RadAiFinding> _findings(Map<String, dynamic>? run) {
    if (run == null) return const [];
    final list = run['findings'] as List? ?? const [];
    return [
      for (final f in list)
        if (f is Map) RadAiFinding.fromJson(Map<String, dynamic>.from(f)),
    ];
  }

  Future<void> _runSecondRead() async {
    setState(() {
      _running = true;
      _error = null;
    });

    try {
      final p = widget.pane;
      if (p == null || !p.hasImage) {
        throw StateError('Please open an image in the viewer first.');
      }
      final view = await radRenderPaneView(
        p,
        annotations: const [],
        mmPerPx: null,
        withAnnotations: false,
      );
      if (view == null) {
        throw StateError('Could not render image pixels.');
      }
      final pngBytes = await radEncodePng(view);
      view.dispose();
      if (pngBytes == null) {
        throw StateError('Could not encode image to PNG.');
      }

      final ai = ref.read(radAiProviderProvider);
      final modality = widget.study.modality == RadModality.other
          ? 'Dental X-Ray'
          : widget.study.modality.label;
      final findings = await ai.secondRead(pngBytes, modality: modality);

      final runId = const Uuid().v4();
      final run = {
        'id': runId,
        'imageId': widget.imageId,
        'at': DateTime.now().millisecondsSinceEpoch,
        'model': GeminiJsonClient.fallbackModel,
        'findings': [for (final f in findings) f.toJson()],
      };

      final updated = widget.study.copyWith(aiReads: [...widget.study.aiReads, run]);
      final ctl = ref.read(radiologyProvider);
      await ctl.saveStudy(updated);
      await ctl.log(
        'Ran AI second read',
        targetKind: 'study',
        targetId: widget.study.id,
        detail: '${findings.length} findings from ${GeminiJsonClient.fallbackModel}',
      );
      if (mounted) {
        radToast(context, 'AI second read: ${findings.length} findings found');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = "Couldn't reach the AI: $e";
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  Future<void> _updateStatus(String findingId, String status) async {
    final aiReads = <Map<String, dynamic>>[];
    RadAiFinding? updatedFinding;

    for (final run in widget.study.aiReads) {
      final runMap = Map<String, dynamic>.from(run);
      if (runMap['imageId'] == widget.imageId) {
        final findingsList = <dynamic>[];
        for (final item in (runMap['findings'] as List? ?? const [])) {
          if (item is Map) {
            final fMap = Map<String, dynamic>.from(item);
            if (fMap['id'] == findingId) {
              fMap['status'] = status;
              updatedFinding = RadAiFinding.fromJson(fMap);
            }
            findingsList.add(fMap);
          } else {
            findingsList.add(item);
          }
        }
        runMap['findings'] = findingsList;
      }
      aiReads.add(runMap);
    }

    final updatedStudy = widget.study.copyWith(aiReads: aiReads);
    final ctl = ref.read(radiologyProvider);
    await ctl.saveStudy(updatedStudy);

    if (updatedFinding != null) {
      final action = status == 'accepted'
          ? 'Accepted AI finding'
          : (status == 'rejected' ? 'Rejected AI finding' : 'Edited AI finding');
      final toothInfo = updatedFinding.tooth.isNotEmpty ? 'Tooth ${updatedFinding.tooth}: ' : '';
      await ctl.log(
        action,
        targetKind: 'study',
        targetId: widget.study.id,
        detail: '$toothInfo${updatedFinding.label}',
      );
    }
  }

  Future<void> _editFinding(RadAiFinding f) async {
    final labelCtrl = TextEditingController(text: f.label);
    final toothCtrl = TextEditingController(text: f.tooth);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit AI Finding'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CruTextField(label: 'Finding label', controller: labelCtrl),
            const SizedBox(height: CruSpace.s12),
            CruTextField(label: 'Tooth (FDI)', controller: toothCtrl),
          ],
        ),
        actions: [
          CruButton(
            label: 'Cancel',
            kind: CruButtonKind.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          CruButton(
            label: 'Save',
            kind: CruButtonKind.primary,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final newLabel = labelCtrl.text.trim();
    final newTooth = toothCtrl.text.trim();

    final aiReads = <Map<String, dynamic>>[];
    for (final run in widget.study.aiReads) {
      final runMap = Map<String, dynamic>.from(run);
      if (runMap['imageId'] == widget.imageId) {
        final findingsList = <dynamic>[];
        for (final item in (runMap['findings'] as List? ?? const [])) {
          if (item is Map) {
            final fMap = Map<String, dynamic>.from(item);
            if (fMap['id'] == f.id) {
              fMap['label'] = newLabel;
              fMap['tooth'] = newTooth;
              fMap['status'] = 'edited';
            }
            findingsList.add(fMap);
          } else {
            findingsList.add(item);
          }
        }
        runMap['findings'] = findingsList;
      }
      aiReads.add(runMap);
    }

    final updatedStudy = widget.study.copyWith(aiReads: aiReads);
    final ctl = ref.read(radiologyProvider);
    await ctl.saveStudy(updatedStudy);
    await ctl.log(
      'Edited AI finding',
      targetKind: 'study',
      targetId: widget.study.id,
      detail: '${newTooth.isNotEmpty ? "Tooth $newTooth: " : ""}$newLabel',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final on = ref.watch(radSettingsProvider).value?.ai('secondRead') ?? false;
    final aiProvider = ref.watch(radAiProviderProvider);
    final connected = aiProvider.connected;
    final numbering = ref.watch(toothNumberingProvider).value ?? ToothNumbering.fdi;
    final showMarks = ref.watch(radShowAiMarksProvider);
    final latestRun = _latestRun();
    final findings = _findings(latestRun);

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
            if (widget.onClose != null)
              CruIconButton(
                icon: CruIcons.close,
                size: CruSize.squareButton,
                iconSize: 18,
                semanticLabel: 'Close',
                tooltip: 'Close',
                onPressed: widget.onClose,
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
        else if (!connected) ...[
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
        ] else ...[
          RadAiActionButton(
            label: _running ? 'Running second read...' : 'Run AI second read',
            onPressed: _running ? null : _runSecondRead,
            expand: true,
          ),
          if (_running) ...[
            const SizedBox(height: CruSpace.s12),
            const LinearProgressIndicator(),
            const SizedBox(height: CruSpace.s6),
            Text(
              'Analyzing de-identified pixels with Gemini...',
              style: CruType.caption.tint(c.label2),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: CruSpace.s10),
            Text(_error!, style: CruType.caption.tint(c.amberText)),
          ],
          if (findings.isNotEmpty) ...[
            const SizedBox(height: CruSpace.s16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Overlay marks',
                    style: CruType.caption.w600.tint(c.label2),
                  ),
                ),
                _AiToggle(
                  label: 'Show AI marks',
                  value: showMarks,
                  onChanged: (v) => ref.read(radShowAiMarksProvider.notifier).state = v,
                ),
              ],
            ),
            const SizedBox(height: CruSpace.s12),
            for (final kind in RadAiKind.values)
              if (findings.any((f) => f.kind == kind)) ...[
                Padding(
                  padding: const EdgeInsets.only(top: CruSpace.s12, bottom: CruSpace.s8),
                  child: Text(
                    kind.label,
                    style: CruType.groupLabel.tint(c.label2),
                  ),
                ),
                for (final f in findings.where((f) => f.kind == kind))
                  Padding(
                    padding: const EdgeInsets.only(bottom: CruSpace.s8),
                    child: CruCard(
                      padding: const EdgeInsets.all(CruSpace.s12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CruIcon(CruIcons.sparkle, size: 14, color: c.ai),
                              const SizedBox(width: CruSpace.s4),
                              Text('AI suggestion', style: CruType.micro.w600.tint(c.ai)),
                              const Spacer(),
                              CruPill(
                                text: '${(f.confidence * 100).round()}%',
                                background: c.aiTint,
                                foreground: c.ai,
                              ),
                              const SizedBox(width: CruSpace.s4),
                              if (f.isAccepted)
                                CruPill(
                                  text: 'Accepted',
                                  background: c.greenTint,
                                  foreground: c.greenText,
                                )
                              else if (f.isRejected)
                                CruPill(
                                  text: 'Rejected',
                                  background: c.inset,
                                  foreground: c.label3,
                                )
                              else if (f.isEdited)
                                CruPill(
                                  text: 'Edited',
                                  background: c.amberTint,
                                  foreground: c.amberText,
                                ),
                            ],
                          ),
                          const SizedBox(height: CruSpace.s8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (f.tooth.isNotEmpty) ...[
                                CruPill(
                                  text: toothLabel(f.tooth, numbering),
                                  background: c.inset,
                                  foreground: c.label,
                                ),
                                const SizedBox(width: CruSpace.s8),
                              ],
                              Expanded(
                                child: Text(
                                  f.label,
                                  style: CruType.callout.w600.tint(c.label),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: CruSpace.s10),
                          Row(
                            children: [
                              CruCapsuleButton(
                                label: 'Accept',
                                icon: CruIcons.check,
                                onPressed: f.isAccepted
                                    ? null
                                    : () => _updateStatus(f.id, 'accepted'),
                              ),
                              const SizedBox(width: CruSpace.s6),
                              CruCapsuleButton(
                                label: 'Reject',
                                icon: CruIcons.close,
                                onPressed: f.isRejected
                                    ? null
                                    : () => _updateStatus(f.id, 'rejected'),
                              ),
                              const Spacer(),
                              CruIconButton(
                                icon: CruIcons.pen,
                                semanticLabel: 'Edit',
                                tooltip: 'Edit finding',
                                onPressed: () => _editFinding(f),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
          ],
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
