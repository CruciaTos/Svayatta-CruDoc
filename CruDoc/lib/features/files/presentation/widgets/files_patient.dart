import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/utils/search_normalisation.dart';
import 'package:doctor_management_app/features/files/data/files_providers.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/files_style.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Patients matching what was typed in the search field (phones). Picking
/// one limits the list to that patient.
class FilesPatientSuggestions extends ConsumerWidget {
  const FilesPatientSuggestions({super.key, required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.cru;
    final q = normalizeForSearch(query);
    final matches = <({String id, String name, String phone})>[];
    if (q.isNotEmpty) {
      final phone = normalizePhoneDigits(query);
      for (final p in ref.watch(patientsStreamProvider).value ?? const []) {
        if (normalizeForSearch(p.fullName).contains(q) ||
            (phone.isNotEmpty &&
                normalizePhoneDigits(p.phone).contains(phone))) {
          matches.add((id: p.id, name: p.fullName, phone: p.phone.trim()));
          if (matches.length == 4) break;
        }
      }
    }
    return AnimatedSize(
      duration: CruMotion.of(context, CruMotion.fast),
      curve: CruMotion.curve,
      alignment: Alignment.topCenter,
      child: matches.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: CruSpace.s8),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: ShapeDecoration(
                  color: c.surface,
                  shape: cruShape(
                    CruRadius.control,
                    side: BorderSide(color: c.hairline),
                  ),
                ),
                child: Column(
                  children: [
                    for (final p in matches)
                      CruPressable(
                        semanticLabel: 'Show files for ${p.name}',
                        onTap: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          ref
                              .read(filesControllerProvider.notifier)
                              .showPatient(p.id);
                        },
                        builder: (context, hovered) => Container(
                          color: hovered ? c.hoverFill : c.surface,
                          padding: const EdgeInsets.symmetric(
                            horizontal: CruSpace.s14,
                            vertical: CruSpace.s8,
                          ),
                          child: Row(
                            children: [
                              CruMonogram(
                                name: p.name,
                                size: 32,
                                showRing: false,
                              ),
                              const SizedBox(width: CruSpace.s12),
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: CruType.text.w500.tint(c.label),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (p.phone.isNotEmpty) ...[
                                const SizedBox(width: CruSpace.s8),
                                Text(
                                  p.phone,
                                  style: CruType.text.tabular.tint(c.label2),
                                ),
                              ],
                            ],
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

/// A square inset button with the new-folder icon. [size] 44 is the
/// thumb-sized one beside Add files; 36 sits on the folder path row.
class FilesFolderButton extends StatelessWidget {
  const FilesFolderButton({
    super.key,
    required this.onPressed,
    this.size = 36,
    this.expand = false,
  });

  final VoidCallback? onPressed;
  final double size;

  /// Fills the width it is given (beside an Add files button of equal
  /// width) instead of being square.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CruPressable(
      onTap: onPressed,
      semanticLabel: 'New folder',
      tooltip: 'New folder',
      builder: (context, hovered) => AnimatedContainer(
        duration: CruMotion.of(context, CruMotion.fast),
        curve: CruMotion.curve,
        width: expand ? double.infinity : size,
        height: size,
        alignment: Alignment.center,
        decoration: ShapeDecoration(
          color: hovered ? c.hoverFill : c.inset,
          shape: cruShape(CruRadius.control),
          shadows: const [],
        ),
        child: CruIcon(
          FileIcons.folderPlus,
          size: size >= 44 ? 22 : 19,
          strokeWidth: 1.8,
          color: c.label2,
        ),
      ),
    );
  }
}

/// The chosen patient, WhatsApp-style (back arrow, avatar, name, count),
/// sliding down from the very top of the screen over the page's own back
/// bar, and back up when the patient is cleared. [name] null hides it.
class PatientTopBanner extends StatefulWidget {
  const PatientTopBanner({
    super.key,
    required this.name,
    required this.subtitle,
    required this.onBack,
  });

  final String? name;
  final String subtitle;
  final VoidCallback onBack;

  @override
  State<PatientTopBanner> createState() => _PatientTopBannerState();
}

class _PatientTopBannerState extends State<PatientTopBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this);
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1),
    end: Offset.zero,
  ).chain(CurveTween(curve: CruMotion.curve)).animate(_anim);

  /// What the banner shows; kept while it slides away.
  final ValueNotifier<(String, String)> _shown = ValueNotifier(('', ''));
  OverlayEntry? _entry;

  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(PatientTopBanner old) {
    super.didUpdateWidget(old);
    _scheduleSync();
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
    _anim.dispose();
    _shown.dispose();
    super.dispose();
  }

  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _sync();
    });
  }

  void _sync() {
    final name = widget.name;
    _anim.duration = CruMotion.of(context, CruMotion.pane);
    if (name != null) {
      _shown.value = (name, widget.subtitle);
      if (_entry == null) {
        _entry = OverlayEntry(builder: _buildEntry);
        Overlay.of(context).insert(_entry!);
      }
      _anim.forward();
    } else if (_entry != null) {
      _anim.reverse().whenComplete(() {
        if (!mounted || !_anim.isDismissed) return;
        _entry?.remove();
        _entry?.dispose();
        _entry = null;
      });
    }
  }

  Widget _buildEntry(BuildContext overlayContext) {
    final secondary = ModalRoute.of(context)?.secondaryAnimation;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: secondary ?? _anim,
        builder: (context, child) =>
            // A page opened on top (a file) covers the banner.
            (secondary?.value ?? 0) > 0 ? const SizedBox.shrink() : child!,
        child: SlideTransition(
          position: _slide,
          child: ValueListenableBuilder<(String, String)>(
            valueListenable: _shown,
            builder: (context, data, _) {
              final c = context.cru;
              return Material(
                color: c.surface,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: c.hairline)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top,
                      left: CruSpace.s4,
                      right: CruSpace.s16,
                    ),
                    child: SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          CruIconButton(
                            icon: CruIcons.chevronLeft,
                            size: 44,
                            iconSize: 24,
                            semanticLabel: 'Show files for everyone',
                            onPressed: widget.onBack,
                          ),
                          const SizedBox(width: CruSpace.s4),
                          CruMonogram(name: data.$1, size: 40, showRing: false),
                          const SizedBox(width: CruSpace.s12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data.$1,
                                  style: CruType.row.w600.tint(c.label),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  data.$2,
                                  style: CruType.text.tabular.tint(c.label2),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
