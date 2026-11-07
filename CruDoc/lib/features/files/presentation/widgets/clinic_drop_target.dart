import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:doctor_management_app/core/pdf/data/branding_image_store.dart';
import 'package:doctor_management_app/core/pdf/data/doc_repository.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/colleague_strip.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/share_drag_stage.dart';
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

/// The phone's colleague strip: the clinic logo (or the CruDoc mark when the
/// clinic has none). While a file is held it stays lit above the dimmed
/// screen; dragging the file onto it pops out a row of colleague avatars
/// (Instagram's hold-to-share): release on one to send (direct on clinic
/// Wi-Fi, otherwise through the cloud), with Undo. Tapping it shows the
/// colleagues as a list with each one's delivery ring.
class ClinicDropTarget extends ConsumerWidget {
  const ClinicDropTarget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logo = ref.watch(clinicLogoBytesProvider).value;
    final colleagues = ref.watch(stripColleaguesProvider);
    // Keeps the Wi-Fi check running while Files is open, as the desktop
    // strip does, so the list opens already knowing who is here.
    ref.watch(colleaguesOnWifiProvider);
    final waiting = ref.watch(
      colleagueDeliveryProvider.select(
        (d) => d.values.fold<int>(0, (n, x) => n + x.waiting.length),
      ),
    );

    return Semantics(
      button: true,
      label:
          'Send to a colleague. Drag a file here, then '
          'onto a colleague.',
      child: ColleagueShareFan(
        members: colleagues,
        builder: (context, fanOpen) => ValueListenableBuilder<bool>(
          valueListenable: ShareDragStage.active,
          builder: (context, dragging, _) => ColleagueDropMenu(
            members: colleagues,
            holdToOpen: Duration.zero,
            opensOnDrag: false,
            builder: (context, menuOpen) => _tile(
              context,
              logo: logo,
              waiting: waiting,
              hovering: fanOpen || menuOpen,
              // A file is held: the logo is where it can go.
              calling: dragging,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required Uint8List? logo,
    required int waiting,
    required bool hovering,
    required bool calling,
  }) {
    final c = context.cru;
    final motion = CruMotion.of(context, CruMotion.fast);
    return WaitingBadge(
      count: waiting,
      from: 1,
      child: AnimatedScale(
        scale: hovering ? 1.08 : 1,
        duration: motion,
        curve: CruMotion.curve,
        child: AnimatedContainer(
          duration: motion,
          curve: CruMotion.curve,
          width: CruSize.searchBar,
          height: CruSize.searchBar,
          padding: const EdgeInsets.all(CruSpace.s6),
          decoration: ShapeDecoration(
            color: hovering ? c.accentTint : c.surface,
            shape: cruShape(
              CruRadius.control,
              side: BorderSide(
                color: hovering || calling ? c.accent : c.hairline,
                width: calling && !hovering ? 1.5 : 1,
              ),
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
