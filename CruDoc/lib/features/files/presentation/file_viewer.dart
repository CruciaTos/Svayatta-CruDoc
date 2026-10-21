import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/progressive_picture.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Desktop: files can also be handed to the computer's own apps.
bool get filesOnDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// A picture or PDF opened inside CruDoc, full screen. Esc closes it.
/// Opens at once: its thumbnail shows while the file itself downloads.
class FileViewerPage extends StatelessWidget {
  const FileViewerPage({
    super.key,
    required this.file,
    required this.patientName,
  });

  final PatientFile file;
  final String patientName;

  bool get _isPdf => file.contentType == 'application/pdf';

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: c.canvas,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    CruSpace.s12,
                    CruSpace.s12,
                    CruSpace.s16,
                    CruSpace.s12,
                  ),
                  child: Row(
                    children: [
                      CruIconButton(
                        icon: CruIcons.chevronLeft,
                        semanticLabel: 'Back',
                        tooltip: 'Back (Esc)',
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: CruSpace.s8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.name,
                              style: CruType.headline.tint(c.label),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              patientName,
                              style: CruType.subhead.tint(c.label2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (filesOnDesktop) ...[
                        const SizedBox(width: CruSpace.s12),
                        CruButton(
                          label: 'Open in another app',
                          kind: CruButtonKind.secondary,
                          icon: CruIcons.arrowUpRight,
                          onPressed: () => _openElsewhere(context),
                        ),
                      ],
                    ],
                  ),
                ),
                const CruSeparator(),
                Expanded(child: _isPdf ? _pdf(context) : _image(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _image(BuildContext context) => ProgressivePicture(file: file);

  Widget _pdf(BuildContext context) => _PdfView(file: file);

  /// The original, downloaded first when needed, in the computer's own app.
  Future<void> _openElsewhere(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final local = await FilesRepository.instance.localCopy(file);
      await launchUrl(Uri.file(local.path));
    } on FilesException catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating),
      );
    }
  }
}

/// A PDF. Its first page's thumbnail sits exactly where the real first
/// page will be; once the document has rendered underneath, the thumbnail
/// melts away from blurred to clear, so nothing moves or snaps.
class _PdfView extends StatefulWidget {
  const _PdfView({required this.file});

  final PatientFile file;

  @override
  State<_PdfView> createState() => _PdfViewState();
}

class _PdfViewState extends State<_PdfView>
    with SingleTickerProviderStateMixin {
  /// The page layout, shared by the placeholder and the document.
  static const double _maxPageWidth = 720;
  static const EdgeInsets _pageMargin = EdgeInsets.all(CruSpace.s16);

  late Future<File> _local = FilesRepository.instance.localCopy(widget.file);
  late final AnimationController _dissolve =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) setState(() {});
      });
  bool _rendered = false;

  @override
  void dispose() {
    _dissolve.dispose();
    super.dispose();
  }

  /// The document's pages are on screen under the placeholder.
  void _onRendered() {
    if (_rendered || !mounted) return;
    _rendered = true;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      _dissolve.value = 1;
    } else {
      _dissolve.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final thumb = fileThumbBytes(widget.file);
    final size = jpegSize(thumb);
    final placeholder = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxPageWidth),
        child: Padding(
          padding: _pageMargin,
          child: AspectRatio(
            aspectRatio: size == null ? 210 / 297 : size.width / size.height,
            child: _PdfPage(thumb: thumb),
          ),
        ),
      ),
    );
    return FutureBuilder<File>(
      future: _local,
      builder: (context, snap) {
        final local = snap.data;
        if (snap.hasError) {
          final error = snap.error;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error is FilesException
                      ? error.message
                      : "Couldn't download this PDF. Check the connection and try again.",
                  textAlign: TextAlign.center,
                  style: CruType.text.tint(c.label2),
                ),
                const SizedBox(height: CruSpace.s12),
                CruButton(
                  label: 'Try again',
                  kind: CruButtonKind.secondary,
                  onPressed: () => setState(() {
                    _local = FilesRepository.instance.localCopy(widget.file);
                  }),
                ),
              ],
            ),
          );
        }
        if (local == null) return placeholder;
        return Stack(
          fit: StackFit.expand,
          children: [
            PdfPreview.builder(
              build: (_) => local.readAsBytes(),
              // Every page comes in the same way, top to bottom.
              pagesBuilder: (context, pages) => InteractiveViewer(
                panEnabled: false,
                maxScale: 5,
                child: ListView.builder(
                  itemCount: pages.length,
                  itemBuilder: (context, i) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _maxPageWidth,
                      ),
                      child: _PageIn(
                        index: i,
                        child: Padding(
                          padding: _pageMargin,
                          child: DecoratedBox(
                            decoration: _PdfPage.decoration,
                            child: AspectRatio(
                              aspectRatio: pages[i].width / pages[i].height,
                              child: Image(
                                image: pages[i].image,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              pdfFileName: widget.file.name,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              allowPrinting: true,
              allowSharing: true,
              useActions: true,
              maxPageWidth: _maxPageWidth,
              padding: EdgeInsets.zero,
              previewPageMargin: _pageMargin,
              scrollViewDecoration: BoxDecoration(color: c.canvas),
              pdfPreviewPageDecoration: _PdfPage.decoration,
              loadingWidget: _WhenGone(onGone: _onRendered),
              onError: (context, error) => Center(
                child: Text(
                  "This PDF can't be shown here.",
                  style: CruType.text.tint(c.label2),
                ),
              ),
            ),
            if (!_dissolve.isCompleted)
              IgnorePointer(
                // The soft thumbnail melts away over the sharp pages.
                child: AnimatedBuilder(
                  animation: _dissolve,
                  builder: (context, child) {
                    final t = CruMotion.curve.transform(_dissolve.value);
                    return Opacity(
                      opacity: 1 - t,
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(
                          sigmaX: 1 + 12 * t,
                          sigmaY: 1 + 12 * t,
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: placeholder,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A sheet of paper with the first page's thumbnail, softened, and the
/// loading light over it.
class _PdfPage extends StatefulWidget {
  const _PdfPage({required this.thumb});

  final Uint8List? thumb;

  /// Paper is white whatever the theme: PDFs are drawn for it.
  static const BoxDecoration decoration = BoxDecoration(
    color: Colors.white,
    boxShadow: [
      BoxShadow(color: Color(0x1F000000), offset: Offset(0, 2), blurRadius: 8),
    ],
  );

  @override
  State<_PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<_PdfPage>
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
    final thumb = widget.thumb;
    return DecoratedBox(
      decoration: _PdfPage.decoration,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumb != null)
            ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: 3,
                  sigmaY: 3,
                  tileMode: TileMode.clamp,
                ),
                child: Image.memory(
                  thumb,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                ),
              ),
            ),
          LoadingSweep(animation: _sweep),
        ],
      ),
    );
  }
}

/// Calls [onGone] when it leaves the tree: PdfPreview drops its loading
/// widget once the pages are drawn.
class _WhenGone extends StatefulWidget {
  const _WhenGone({required this.onGone});

  final VoidCallback onGone;

  @override
  State<_WhenGone> createState() => _WhenGoneState();
}

class _WhenGoneState extends State<_WhenGone> {
  @override
  void dispose() {
    final gone = widget.onGone;
    WidgetsBinding.instance.addPostFrameCallback((_) => gone());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// A page arriving: it fades in from blurred to sharp and settles into
/// place, each page a beat after the one above it.
class _PageIn extends StatelessWidget {
  const _PageIn({required this.index, required this.child});

  final int index;
  final Widget child;

  static const _each = Duration(milliseconds: 600);
  static const _beat = Duration(milliseconds: 120);

  @override
  Widget build(BuildContext context) {
    final delay = _beat * (index < 8 ? index : 8);
    final total = _each + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: CruMotion.of(context, total),
      curve: Interval(
        delay.inMilliseconds / total.inMilliseconds,
        1,
        curve: CruMotion.curve,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * CruSpace.s16),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: (1 - t) * 10,
              sigmaY: (1 - t) * 10,
            ),
            child: child,
          ),
        ),
      ),
      child: child,
    );
  }
}
