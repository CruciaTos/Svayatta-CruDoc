import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
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

/// PDF viewing canvas is always off-white even in evening/dark mode.
const Color _pdfCanvasColor = Color(0xFFEFF1F5);

/// One rendered page of a PDF. [sharp] is the page at screen resolution;
/// [soft] is a quarter-size copy that is always kept, so a page never
/// shows blank, even in a document too long to hold sharp in memory.
class _PdfPageImage {
  _PdfPageImage({
    required this.width,
    required this.height,
    required this.sharp,
    required this.soft,
  });

  final int width;
  final int height;
  ui.Image? sharp;
  final ui.Image soft;

  /// When it arrived, for the arrival animation.
  final DateTime arrivedAt = DateTime.now();

  int get bytes => width * height * 4;
  double get aspectRatio => height == 0 ? 210 / 297 : width / height;
}

/// A PDF's pages, rendered once, in order, and kept: scrolling back to a
/// page shows it straight away instead of rendering it again. Only a
/// document over the memory budget lets go of its farthest pages' sharp
/// copies (their soft copies stay on screen until they come back).
class _PdfPages extends ChangeNotifier {
  _PdfPages({required this.bytes, required this.dpi}) {
    _queue = _load();
  }

  final Uint8List bytes;
  final double dpi;
  final List<_PdfPageImage> pages = [];
  bool done = false;
  Object? error;

  /// Sharp pages kept in memory, in bytes.
  static int get _budget =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS) ? 192 << 20 : 448 << 20;

  int _held = 0;
  bool _disposed = false;
  late Future<void> _queue;
  final Set<int> _wanted = {};

  /// How many tiles show each page right now (the list's built range).
  final Map<int, int> _live = {};

  Future<void> _load() async {
    try {
      await for (final raster in Printing.raster(bytes, dpi: dpi)) {
        if (_disposed) return;
        final sharp = await raster.toImage();
        if (_disposed) {
          sharp.dispose();
          return;
        }
        final soft = await _shrink(sharp);
        pages.add(
          _PdfPageImage(
            width: raster.width,
            height: raster.height,
            sharp: sharp,
            soft: soft,
          ),
        );
        _held += pages.last.bytes;
        _trim();
        notifyListeners();
      }
    } catch (e) {
      error = e;
    }
    done = true;
    if (!_disposed) notifyListeners();
  }

  static Future<ui.Image> _shrink(ui.Image image) {
    final w = math.max(1, image.width ~/ 4);
    final h = math.max(1, image.height ~/ 4);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final picture = recorder.endRecording();
    return picture.toImage(w, h).whenComplete(picture.dispose);
  }

  void showing(int index) => _live[index] = (_live[index] ?? 0) + 1;

  void hidden(int index) {
    final n = (_live[index] ?? 1) - 1;
    if (n <= 0) {
      _live.remove(index);
    } else {
      _live[index] = n;
    }
  }

  /// Over budget: drop the sharp copies farthest from what is on screen.
  void _trim() {
    while (_held > _budget) {
      // Nothing on screen yet: the reader starts at the top.
      final near = _live.isEmpty ? const [0] : _live.keys;
      int? far;
      var farthest = -1;
      for (var i = 0; i < pages.length; i++) {
        if (pages[i].sharp == null || _live.containsKey(i)) continue;
        final d = near.map((l) => (l - i).abs()).reduce(math.min);
        if (d > farthest) {
          farthest = d;
          far = i;
        }
      }
      if (far == null) return;
      pages[far].sharp!.dispose();
      pages[far].sharp = null;
      _held -= pages[far].bytes;
    }
  }

  /// Brings back a page whose sharp copy was let go.
  void want(int index) {
    if (index >= pages.length || pages[index].sharp != null) return;
    if (!_wanted.add(index)) return;
    _queue = _queue.then((_) async {
      try {
        if (_disposed || pages[index].sharp != null) return;
        final raster = await Printing.raster(
          bytes,
          pages: [index],
          dpi: dpi,
        ).first;
        final sharp = await raster.toImage();
        if (_disposed) {
          sharp.dispose();
          return;
        }
        pages[index].sharp = sharp;
        _held += pages[index].bytes;
        _trim();
        notifyListeners();
      } catch (e) {
        debugPrint('[PdfPages] page ${index + 1}: $e');
      } finally {
        _wanted.remove(index);
      }
    });
  }

  /// [index] at [scale] times the screen resolution, for the zoomed page.
  /// The caller owns (and disposes) it.
  Future<ui.Image?> zoomed(int index, double scale) {
    final done = Completer<ui.Image?>();
    _queue = _queue.then((_) async {
      try {
        if (_disposed) {
          done.complete(null);
          return;
        }
        final raster = await Printing.raster(
          bytes,
          pages: [index],
          dpi: dpi * scale,
        ).first;
        done.complete(await raster.toImage());
      } catch (e) {
        debugPrint('[PdfPages] zoom ${index + 1}: $e');
        done.complete(null);
      }
    });
    return done.future;
  }

  @override
  void dispose() {
    _disposed = true;
    for (final p in pages) {
      p.sharp?.dispose();
      p.soft.dispose();
    }
    pages.clear();
    super.dispose();
  }
}

/// A PDF. Its first page's thumbnail sits exactly where the real first
/// page will be; once that page is drawn, the thumbnail melts away from
/// blurred to clear, and the pages after it rise in one after another as
/// they arrive. That entrance plays once: after it, every page stays
/// drawn and scrolling never loads a page again.
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

  late final AnimationController _dissolve =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) setState(() {});
      });

  _PdfPages? _pages;
  Object? _error;
  bool _opening = false;
  bool _rendered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pages == null && !_opening && _error == null) unawaited(_open());
  }

  @override
  void dispose() {
    _dissolve.dispose();
    _pages?.dispose();
    super.dispose();
  }

  /// Pixels per inch that fill the page width on this screen.
  double _dpi() {
    final mq = MediaQuery.of(context);
    final width = math.min(mq.size.width, _maxPageWidth) - _pageMargin.horizontal;
    final ratio = mq.devicePixelRatio.clamp(1.0, 3.0);
    return math.max(48, width) * ratio / PdfPageFormat.a4.width * 72;
  }

  Future<void> _open() async {
    _opening = true;
    final dpi = _dpi();
    try {
      final local = await FilesRepository.instance.localCopy(widget.file);
      final bytes = await local.readAsBytes();
      if (!mounted) return;
      final pages = _PdfPages(bytes: bytes, dpi: dpi)..addListener(_changed);
      setState(() => _pages = pages);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      _opening = false;
    }
  }

  void _retry() {
    _pages?.dispose();
    setState(() {
      _pages = null;
      _error = null;
      _rendered = false;
      _dissolve.value = 0;
    });
    unawaited(_open());
  }

  void _changed() {
    final pages = _pages;
    if (pages == null || !mounted) return;
    if (!_rendered && pages.pages.isNotEmpty) {
      // The first page is drawn under the placeholder.
      _rendered = true;
      final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduced) {
        _dissolve.value = 1;
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _dissolve.forward(from: 0);
        });
      }
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
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
    final pages = _pages;
    final error =
        _error ??
        (pages != null && pages.done && pages.pages.isEmpty
            ? pages.error ?? const FormatException()
            : null);
    if (error != null) {
      return ColoredBox(
        color: _pdfCanvasColor,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error is FilesException
                    ? error.message
                    : pages == null
                    ? "Couldn't download this PDF. Check the connection and try again."
                    : "This PDF can't be shown here.",
                textAlign: TextAlign.center,
                style: CruType.text.tint(const Color(0xFF475569)),
              ),
              const SizedBox(height: CruSpace.s12),
              CruButton(
                label: 'Try again',
                kind: CruButtonKind.secondary,
                onPressed: _retry,
              ),
            ],
          ),
        ),
      );
    }
    return ColoredBox(
      color: _pdfCanvasColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (pages != null && pages.pages.isNotEmpty)
            _PdfDocumentViewer(
              pages: pages,
              name: widget.file.name,
              maxPageWidth: _maxPageWidth,
              pageMargin: _pageMargin,
            ),
          if (!_dissolve.isCompleted)
            IgnorePointer(
              // The soft thumbnail melts away over the sharp first page.
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
      ),
    );
  }
}

/// The pages top to bottom. Double-tap a page to open it on its own,
/// sharper, to pan and zoom; double-tap or Esc to come back.
class _PdfDocumentViewer extends StatefulWidget {
  const _PdfDocumentViewer({
    required this.pages,
    required this.name,
    required this.maxPageWidth,
    required this.pageMargin,
  });

  final _PdfPages pages;
  final String name;
  final double maxPageWidth;
  final EdgeInsets pageMargin;

  @override
  State<_PdfDocumentViewer> createState() => _PdfDocumentViewerState();
}

class _PdfDocumentViewerState extends State<_PdfDocumentViewer> {
  final TransformationController _singlePageTransform =
      TransformationController();
  int? _zoomedPageIndex;
  ui.Image? _zoomedSharp;
  MouseCursor _singlePageCursor = MouseCursor.defer;

  /// Pages that have been on screen: they never play the entrance again.
  final Set<int> _seen = {0};

  @override
  void dispose() {
    _singlePageTransform.dispose();
    _zoomedSharp?.dispose();
    super.dispose();
  }

  Future<void> _enterZoom(int index) async {
    setState(() {
      _zoomedPageIndex = index;
      _singlePageTransform.value = Matrix4.identity();
      _singlePageCursor = SystemMouseCursors.grab;
    });
    // A sharper copy for zooming in, swapped in when it is ready.
    final sharp = await widget.pages.zoomed(index, 2.5);
    if (!mounted || _zoomedPageIndex != index) {
      sharp?.dispose();
      return;
    }
    setState(() {
      _zoomedSharp?.dispose();
      _zoomedSharp = sharp;
    });
  }

  void _exitZoom() {
    if (_zoomedPageIndex == null) return;
    setState(() {
      _zoomedPageIndex = null;
      _zoomedSharp?.dispose();
      _zoomedSharp = null;
      _singlePageCursor = MouseCursor.defer;
    });
  }

  void _updateCursor(MouseCursor cursor) {
    if (_singlePageCursor != cursor) {
      setState(() => _singlePageCursor = cursor);
    }
  }

  Future<void> _print() => Printing.layoutPdf(
    onLayout: (_) async => widget.pages.bytes,
    name: widget.name,
  );

  Future<void> _share() =>
      Printing.sharePdf(bytes: widget.pages.bytes, filename: widget.name);

  @override
  Widget build(BuildContext context) {
    final hasZoom =
        _zoomedPageIndex != null &&
        _zoomedPageIndex! < widget.pages.pages.length;

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(ignoring: hasZoom, child: _buildDocumentList(context)),
        if (!hasZoom)
          Positioned(
            bottom: CruSpace.s16,
            left: 0,
            right: 0,
            child: Center(
              child: _Capsule(
                children: [
                  _CapsuleButton(
                    icon: Icons.print_outlined,
                    label: 'Print',
                    onTap: _print,
                  ),
                  _CapsuleButton(
                    icon: Icons.ios_share,
                    label: 'Share',
                    onTap: _share,
                  ),
                ],
              ),
            ),
          ),
        if (hasZoom) _buildSinglePageZoom(context),
      ],
    );
  }

  Widget _buildDocumentList(BuildContext context) {
    final pages = widget.pages;
    // The page still being drawn waits as blank paper below the others.
    final count = pages.pages.length + (pages.done ? 0 : 1);
    return InteractiveViewer(
      panEnabled: false,
      maxScale: 5,
      minScale: 1,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 72),
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        // Pages a screen or two away are laid out ahead of time.
        cacheExtent: 1600,
        itemCount: count,
        itemBuilder: (context, i) {
          final ready = i < pages.pages.length;
          final page = ready ? pages.pages[i] : null;
          final ratio =
              page?.aspectRatio ??
              (pages.pages.isEmpty
                  ? 210 / 297
                  : pages.pages.last.aspectRatio);
          // A page arriving while it is on screen rises in; one drawn
          // while it was off screen is simply there when scrolled to.
          final arriving =
              page != null &&
              !_seen.contains(i) &&
              DateTime.now().difference(page.arrivedAt) <
                  const Duration(milliseconds: 400);
          if (page != null) _seen.add(i);
          final sheet = Padding(
            padding: widget.pageMargin,
            child: AspectRatio(
              aspectRatio: ratio,
              child: page == null
                  ? const _PdfPage(thumb: null)
                  : DecoratedBox(
                      decoration: _PdfPage.decoration,
                      child: _PdfPageTile(pages: pages, index: i),
                    ),
            ),
          );
          return Center(
            key: ValueKey<String>(ready ? 'page-$i' : 'pending-$i'),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxPageWidth),
              child: GestureDetector(
                onDoubleTap: ready ? () => _enterZoom(i) : null,
                child: _PageIn(play: arriving, child: sheet),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSinglePageZoom(BuildContext context) {
    final index = _zoomedPageIndex!;
    final page = widget.pages.pages[index];
    final image = _zoomedSharp ?? page.sharp ?? page.soft;

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _exitZoom},
      child: Focus(
        autofocus: true,
        child: ColoredBox(
          color: _pdfCanvasColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MouseRegion(
                cursor: _singlePageCursor,
                child: GestureDetector(
                  onDoubleTap: _exitZoom,
                  onLongPressCancel: () =>
                      _updateCursor(SystemMouseCursors.grab),
                  onLongPressDown: (_) =>
                      _updateCursor(SystemMouseCursors.grabbing),
                  child: InteractiveViewer(
                    transformationController: _singlePageTransform,
                    minScale: 0.8,
                    maxScale: 6.0,
                    onInteractionStart: (_) =>
                        _updateCursor(SystemMouseCursors.grabbing),
                    onInteractionEnd: (_) =>
                        _updateCursor(SystemMouseCursors.grab),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: widget.maxPageWidth,
                        ),
                        child: Padding(
                          padding: widget.pageMargin,
                          child: DecoratedBox(
                            decoration: _PdfPage.decoration,
                            child: AspectRatio(
                              aspectRatio: page.aspectRatio,
                              child: RawImage(
                                image: image,
                                fit: BoxFit.fill,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: CruSpace.s16,
                left: 0,
                right: 0,
                child: Center(
                  child: _Capsule(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CruSpace.s8,
                        ),
                        child: Text(
                          'Page ${index + 1} of ${widget.pages.pages.length}',
                          style: CruType.caption.tabular.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (filesOnDesktop)
                        Text(
                          '•  Double-tap or Esc to exit',
                          style: CruType.caption.copyWith(
                            color: const Color(0xFFCBD5E1),
                          ),
                        ),
                      _CapsuleButton(
                        icon: Icons.close,
                        label: 'Back to all pages',
                        onTap: _exitZoom,
                      ),
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

/// One page in the list: its sharp copy, or its soft copy while a page
/// let go for memory is drawn again.
class _PdfPageTile extends StatefulWidget {
  const _PdfPageTile({required this.pages, required this.index});

  final _PdfPages pages;
  final int index;

  @override
  State<_PdfPageTile> createState() => _PdfPageTileState();
}

class _PdfPageTileState extends State<_PdfPageTile> {
  @override
  void initState() {
    super.initState();
    widget.pages.showing(widget.index);
  }

  @override
  void dispose() {
    widget.pages.hidden(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.pages.pages[widget.index];
    final sharp = page.sharp;
    if (sharp == null) widget.pages.want(widget.index);
    return RawImage(
      image: sharp ?? page.soft,
      fit: BoxFit.fill,
      filterQuality: sharp == null ? FilterQuality.medium : FilterQuality.low,
    );
  }
}

/// The dark floating pill at the bottom of the PDF: print and share, or
/// the zoomed page's number.
class _Capsule extends StatelessWidget {
  const _Capsule({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xDE0F172A),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: CruSpace.s8,
        vertical: CruSpace.s4,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _CapsuleButton extends StatelessWidget {
  const _CapsuleButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: label,
      icon: Icon(icon, size: 18, color: Colors.white),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// A sheet of paper with the first page's thumbnail, softened, and the
/// loading light over it.
class _PdfPage extends StatefulWidget {
  const _PdfPage({required this.thumb});

  final Uint8List? thumb;

  /// Paper is white whatever the theme: PDFs are drawn for it.
  /// Heavy layered drop shadows provide strong elevation and physical depth
  /// against the off-white canvas.
  static const BoxDecoration decoration = BoxDecoration(
    color: Colors.white,
    boxShadow: [
      BoxShadow(
        color: Color(0x38000000), // deep ground shadow
        offset: Offset(0, 8),
        blurRadius: 24,
        spreadRadius: 1,
      ),
      BoxShadow(
        color: Color(0x24000000), // mid-level ambient shadow
        offset: Offset(0, 3),
        blurRadius: 10,
      ),
      BoxShadow(
        color: Color(0x1A000000), // crisp edge contact shadow
        offset: Offset(0, 1),
        blurRadius: 3,
      ),
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

/// A page arriving on screen: it fades in from blurred to sharp and
/// settles into place. It plays once, the moment the page first appears;
/// [play] is read only then, so later rebuilds never cut it short.
class _PageIn extends StatefulWidget {
  const _PageIn({required this.play, required this.child});

  final bool play;
  final Widget child;

  @override
  State<_PageIn> createState() => _PageInState();
}

class _PageInState extends State<_PageIn> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
    value: widget.play ? 0 : 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      _t.value = 1;
    } else if (!_t.isAnimating && !_t.isCompleted) {
      _t.forward();
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final t = CruMotion.curve.transform(_t.value);
        if (t >= 1) return child!;
        return Opacity(
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
        );
      },
    );
  }
}
