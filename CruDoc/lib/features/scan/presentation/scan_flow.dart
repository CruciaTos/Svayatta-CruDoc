import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:doctor_management_app/features/appointments/presentation/patient_picker_dialog.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/progressive_picture.dart';
import 'package:doctor_management_app/features/mobile/mobile_kit.dart';
import 'package:doctor_management_app/features/patients/data/models/patient.dart';
import 'package:doctor_management_app/features/scan/data/scan_capture.dart';
import 'package:doctor_management_app/features/scan/presentation/scan_bill_page.dart';
import 'package:doctor_management_app/features/scan/presentation/scan_note_page.dart';
import 'package:doctor_management_app/features/scan/presentation/scan_record_page.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The Scan quick action: the document camera finds the page, saves it
/// once it is steady and sharp, and straightens it, then the person says what the pages are for and the AI
/// reads them into that place. The pages themselves are always kept with
/// what they became.
///
/// [patient] skips the patient question (a scan started from their
/// record). [clinical]: may write clinical records. [inventory]: the
/// inventory module is on and they may stock it. [revenue]: a bill can
/// also be recorded as an expense.
Future<void> startScanFlow(
  BuildContext context, {
  Patient? patient,
  required bool clinical,
  required bool inventory,
  required bool revenue,
}) async {
  final root = mobileRoot(context);
  if (!clinical && !inventory) {
    mobileSay(
      root,
      'Scanning needs permission to write clinical records or manage '
      'inventory.',
    );
    return;
  }
  final List<ScannedPage> pages;
  try {
    pages = await ScanCapture.capture(root);
  } on ScanCaptureException catch (e) {
    if (root.mounted) mobileSay(root, e.message);
    return;
  }
  if (pages.isEmpty || !root.mounted) return;

  Future<Patient?> whose(String title) async =>
      patient ?? await showPatientPickerDialog(root, title: title);

  final count = pages.length == 1 ? '1 page' : '${pages.length} pages';
  await showMobileActionSheet(
    root,
    title: 'Use this scan for',
    subtitle: '$count · cropped and straightened',
    leading: ScanStack(pages: pages),
    actions: [
      if (clinical)
        MobileSheetAction(
          label: 'Session note',
          detail: 'Handwritten notes, written up into session history',
          icon: CruIcons.pen,
          tone: MobileTone.blue,
          onTap: () async {
            final p = await whose('Whose session notes are these?');
            if (p == null || !root.mounted) return;
            await pushMobile(root, ScanNotePage(pages: pages, patient: p));
          },
        ),
      if (clinical)
        MobileSheetAction(
          label: 'Patient record',
          detail: 'A report, prescription or letter, digitised into files',
          icon: CruIcons.fileText,
          tone: MobileTone.sky,
          onTap: () async {
            final p = await whose('Whose record is this?');
            if (p == null || !root.mounted) return;
            await pushMobile(root, ScanRecordPage(pages: pages, patient: p));
          },
        ),
      if (inventory)
        MobileSheetAction(
          label: 'Supplier bill',
          detail: 'Adds the medicines and supplies bought to inventory',
          icon: CruIcons.box,
          tone: MobileTone.teal,
          onTap: () =>
              pushMobile(root, ScanBillPage(pages: pages, revenue: revenue)),
        ),
    ],
  );
}

/// The pages as files for a patient: "Session note 22 Oct 2026 (2).jpg".
List<FileSource> scanFileSources(List<ScannedPage> pages, String baseName) => [
  for (var i = 0; i < pages.length; i++)
    FileSource(
      name: pages.length == 1
          ? '$baseName.jpg'
          : '$baseName (${i + 1} of ${pages.length}).jpg',
      sizeBytes: pages[i].jpeg.lengthInBytes,
      bytes: pages[i].jpeg,
    ),
];

/// A pushed scan page: header, scrolling content, and its one action
/// pinned at the bottom.
class ScanScaffold extends StatelessWidget {
  const ScanScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return MobileHostPage(
      backLabel: 'Back',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.only(bottom: CruSpace.s24),
              children: [
                MobileHeader(title: title, subtitle: subtitle, pushed: true),
                const SizedBox(height: CruSpace.s16),
                ...children,
              ],
            ),
          ),
          if (bottom != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  MobileMetrics.gutter,
                  CruSpace.s8,
                  MobileMetrics.gutter,
                  CruSpace.s12,
                ),
                child: bottom,
              ),
            ),
        ],
      ),
    );
  }
}

/// The scanned pages, fanned slightly: the actions sheet's leading tile.
class ScanStack extends StatelessWidget {
  const ScanStack({super.key, required this.pages});

  final List<ScannedPage> pages;

  @override
  Widget build(BuildContext context) {
    final shown = pages.take(3).toList().reversed.toList();
    return SizedBox(
      width: 48,
      height: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: (shown.length - 1 - i) * 4.0,
              top: (shown.length - 1 - i) * -3.0 + 6,
              child: _Paper(page: shown[i], width: 38),
            ),
        ],
      ),
    );
  }
}

class _Paper extends StatelessWidget {
  const _Paper({required this.page, required this.width});

  final ScannedPage page;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width / page.aspectRatio.clamp(0.5, 1.6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x29000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.memory(page.thumb, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}

/// The pages in a row; a tap opens them full screen.
class ScanPagesStrip extends StatelessWidget {
  const ScanPagesStrip({super.key, required this.pages});

  final List<ScannedPage> pages;

  @override
  Widget build(BuildContext context) {
    const height = 112.0;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
        itemCount: pages.length,
        separatorBuilder: (_, _) => const SizedBox(width: CruSpace.s10),
        itemBuilder: (context, i) => GestureDetector(
          onTap: () =>
              pushMobile(context, _ScanPagesViewer(pages: pages, initial: i)),
          child: _Paper(
            page: pages[i],
            width: (height - 8) * pages[i].aspectRatio.clamp(0.5, 1.6),
          ),
        ),
      ),
    );
  }
}

/// The scanned pages full screen, swiped through, pinch to zoom.
class _ScanPagesViewer extends StatelessWidget {
  const _ScanPagesViewer({required this.pages, required this.initial});

  final List<ScannedPage> pages;
  final int initial;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            PageView.builder(
              controller: PageController(initialPage: initial),
              itemCount: pages.length,
              itemBuilder: (context, i) => InteractiveViewer(
                maxScale: 6,
                child: Center(
                  child: Image.memory(pages[i].jpeg, gaplessPlayback: true),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(CruSpace.s8),
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const CruIcon(CruIcons.close, color: Colors.white),
                  tooltip: 'Close',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// While the AI reads: the first page with the loading light passing over
/// it, and what is happening.
class ScanReading extends StatefulWidget {
  const ScanReading({super.key, required this.page, required this.label});

  final ScannedPage page;
  final String label;

  @override
  State<ScanReading> createState() => _ScanReadingState();
}

class _ScanReadingState extends State<ScanReading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!reduced && !_sweep.isAnimating) _sweep.repeat();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MobileMetrics.gutter),
      child: MobileCard(
        padding: const EdgeInsets.all(CruSpace.s16),
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: AspectRatio(
                aspectRatio: widget.page.aspectRatio.clamp(0.5, 1.6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CruRadius.control),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.memory(
                        widget.page.jpeg,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                      LoadingSweep(animation: _sweep),
                    ],
                  ),
                ),
              ),
            ),
            MobileLoading(widget.label, height: 56),
          ],
        ),
      ),
    );
  }
}

/// The AI couldn't read the pages: why, and another go.
class ScanProblem extends StatelessWidget {
  const ScanProblem({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MobileEmpty(
      icon: CruIcons.scan,
      title: "Couldn't read the scan",
      body: message,
      action: 'Try again',
      onAction: onRetry,
    );
  }
}

/// AI-written content is marked violet: this was read and written up by
/// the AI, and someone should look before it is saved.
class ScanAiNote extends StatelessWidget {
  const ScanAiNote({super.key, required this.text, this.unclear = ''});

  final String text;

  /// What the AI could not read for certain.
  final String unclear;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final (bg, fg) = mobileTone(c, MobileTone.violet);
    final (abg, afg) = mobileTone(c, MobileTone.amber);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MobileMetrics.gutter,
        0,
        MobileMetrics.gutter,
        CruSpace.s12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: CruSpace.s12,
              vertical: CruSpace.s10,
            ),
            decoration: ShapeDecoration(color: bg, shape: cruShape(12)),
            child: Row(
              children: [
                CruIcon(CruIcons.sparkle, size: 16, color: fg),
                const SizedBox(width: CruSpace.s8),
                Expanded(child: Text(text, style: MobileType.caption.tint(fg))),
              ],
            ),
          ),
          if (unclear.trim().isNotEmpty) ...[
            const SizedBox(height: CruSpace.s8),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: CruSpace.s12,
                vertical: CruSpace.s10,
              ),
              decoration: ShapeDecoration(color: abg, shape: cruShape(12)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CruIcon(CruIcons.warning, size: 16, color: afg),
                  const SizedBox(width: CruSpace.s8),
                  Expanded(
                    child: Text(
                      'Check: ${unclear.trim()}',
                      style: MobileType.caption.tint(afg),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A labelled text box on a scan page.
class ScanTextField extends StatelessWidget {
  const ScanTextField({
    super.key,
    required this.label,
    required this.controller,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
    this.enabled = true,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final int minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final bool enabled;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return MobileField(
      label: label,
      child: TextField(
        controller: controller,
        enabled: enabled,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        textCapitalization: TextCapitalization.sentences,
        style: MobileType.input.tint(c.label),
        decoration: InputDecoration.collapsed(
          hintText: hint,
          hintStyle: MobileType.input.tint(c.label3),
        ),
      ),
    );
  }
}
