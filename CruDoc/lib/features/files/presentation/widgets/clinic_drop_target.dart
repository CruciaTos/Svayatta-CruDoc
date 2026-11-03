import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/pdf/data/branding_image_store.dart';
import 'package:doctor_management_app/core/pdf/data/doc_repository.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The clinic logo from Settings → Documents → Clinic details, or null when
/// none is set (or it isn't downloaded and we're offline).
final clinicLogoBytesProvider = FutureProvider.autoDispose<Uint8List?>((
  ref,
) async {
  final logo = ref.watch(
    clinicDocSettingsProvider.select(
      (s) => (s.value?.logoPath ?? '', s.value?.logoSha ?? ''),
    ),
  );
  if (logo.$1.isEmpty || logo.$2.isEmpty) return null;
  final res = await BrandingImageStore.instance.load(logo.$1, logo.$2);
  return res.bytes;
});

/// The phone's colleague drop target: long-press a file and drop it here
/// to pick a colleague to send it to. Shows the clinic logo, or the CruDoc
/// mark when the clinic has none.
class ClinicDropTarget extends ConsumerStatefulWidget {
  const ClinicDropTarget({super.key});

  @override
  ConsumerState<ClinicDropTarget> createState() => _ClinicDropTargetState();
}

class _ClinicDropTargetState extends ConsumerState<ClinicDropTarget> {
  static const _hint = 'Long-press a file and drop it here to send it';

  void _onTap() {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      const SnackBar(
        content: Text('$_hint to a colleague.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final motion = CruMotion.of(context, CruMotion.fast);
    final logo = ref.watch(clinicLogoBytesProvider).value;

    return DragTarget<FileEntry>(
      onWillAcceptWithDetails: (_) {
        HapticFeedback.selectionClick();
        return true;
      },
      onAcceptWithDetails: (d) {
        // Next frame: the drag is still finishing while the sheet opens.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          FilesActions.sendToColleague(context, ref, [d.data.file]);
        });
      },
      builder: (context, candidates, _) {
        final over = candidates.isNotEmpty;
        return Semantics(
          button: true,
          label: 'Send to a colleague. $_hint.',
          excludeSemantics: true,
          child: Tooltip(
            message: 'Drop a file here to send it to a colleague',
            child: GestureDetector(
              onTap: _onTap,
              child: AnimatedScale(
                scale: over ? 1.08 : 1,
                duration: motion,
                curve: CruMotion.curve,
                child: AnimatedContainer(
                  duration: motion,
                  curve: CruMotion.curve,
                  width: CruSize.searchBar,
                  height: CruSize.searchBar,
                  padding: const EdgeInsets.all(CruSpace.s6),
                  decoration: ShapeDecoration(
                    color: over ? c.accentTint : c.surface,
                    shape: cruShape(
                      CruRadius.control,
                      side: BorderSide(color: over ? c.accent : c.hairline),
                    ),
                    shadows: const [],
                  ),
                  child: logo != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(
                            CruRadius.iconTile - CruSpace.s4,
                          ),
                          child: Image.memory(
                            logo,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                        )
                      : const _CruDocMark(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The CruDoc app mark, as in the sidebar and on the sign-in screen.
class _CruDocMark extends StatelessWidget {
  const _CruDocMark();

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return Container(
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: c.accent,
        shape: cruShape(CruRadius.appMark),
      ),
      child: CruIcon(
        CruIcons.plus,
        size: 16,
        strokeWidth: 3.4,
        color: c.onAccent,
      ),
    );
  }
}
