import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Screen displayed when opening a 3D scan (.stl, .ply, .obj).
/// Renders the mesh in 3D (WebView + three.js, served from loopback; offline).
class ScanViewerPlaceholderScreen extends StatelessWidget {
  const ScanViewerPlaceholderScreen({
    super.key,
    required this.filePath,
    required this.fileName,
  });

  final String filePath;
  final String fileName;

  static int? countStlTriangles(File file) {
    try {
      if (!file.existsSync()) return null;
      final length = file.lengthSync();
      if (length < 84) return null;

      final raf = file.openSync(mode: FileMode.read);
      final headerAndCount = raf.readSync(84);
      raf.closeSync();

      final count = ByteData.sublistView(
        headerAndCount,
      ).getUint32(80, Endian.little);
      if (length == 84 + count * 50) {
        return count;
      }

      // If not strict binary format length match, inspect text for ASCII STL
      final sampleSize = math.min(length, 1024 * 512);
      final sampleFile = file.openSync(mode: FileMode.read);
      final sampleBytes = sampleFile.readSync(sampleSize);
      sampleFile.closeSync();

      final text = String.fromCharCodes(sampleBytes);
      if (text.contains('facet normal')) {
        return RegExp(r'facet\s+normal').allMatches(text).length;
      }

      if (count > 0 && count < 20000000) {
        return count;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) => _ScanBody(
    filePath: filePath,
    fileName: fileName,
    owner: this,
  );
}

class _ScanBody extends StatefulWidget {
  const _ScanBody({
    required this.filePath,
    required this.fileName,
    required this.owner,
  });
  final String filePath;
  final String fileName;
  final ScanViewerPlaceholderScreen owner;

  @override
  State<_ScanBody> createState() => _ScanBodyState();
}

class _ScanBodyState extends State<_ScanBody> {
  HttpServer? _server;
  Uri? _url;
  String? _error;
  String? _comparePath;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  Future<void> _start() async {
    try {
      if (!File(widget.filePath).existsSync()) {
        throw 'File not found on disk';
      }
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      server.listen(_handle);
      final fmt = p.extension(widget.filePath).replaceFirst('.', '');
      if (!mounted) return;
      setState(() {
        _url = Uri.parse('http://127.0.0.1:${server.port}/index.html?fmt=$fmt'
            '&name=${Uri.encodeQueryComponent(widget.fileName)}');
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final path = Uri.decodeComponent(req.uri.path);
      if (path.contains('..')) {
        res.statusCode = HttpStatus.forbidden;
      } else if (path == '/mesh') {
        res.headers.contentType = ContentType.binary;
        await res.addStream(File(widget.filePath).openRead());
      } else if (path == '/old' && _comparePath != null) {
        res.headers.contentType = ContentType.binary;
        res.headers.set('Cache-Control', 'no-store');
        await res.addStream(File(_comparePath!).openRead());
      } else {
        final asset = path.startsWith('/vendor/')
            ? 'assets/muscle_viewer$path'
            : 'assets/scan_viewer${path == '/' ? '/index.html' : path}';
        final data = await rootBundle.load(asset);
        res.headers.contentType = path.endsWith('.js')
            ? ContentType('text', 'javascript', charset: 'utf-8')
            : ContentType.html;
        res.add(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      }
    } catch (_) {
      res.statusCode = HttpStatus.notFound;
    } finally {
      await res.close();
    }
  }

  static const _scanExts = {'.stl', '.ply', '.obj'};

  /// Lets the user pick the second ("old") scan: other scans in the same
  /// folder first, or any file via the file picker.
  Future<Map<String, String>?> _pickCompare() async {
    String? chosen;
    final siblings = <File>[];
    try {
      final dir = Directory(p.dirname(widget.filePath));
      for (final e in dir.listSync()) {
        if (e is File &&
            e.path != widget.filePath &&
            _scanExts.contains(p.extension(e.path).toLowerCase())) {
          siblings.add(e);
        }
      }
      siblings.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
    } catch (_) {}
    if (!mounted) return null;
    if (siblings.isEmpty) {
      chosen = await _browseScan();
    } else {
      final c = context.cru;
      chosen = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: c.canvas,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(CruSpace.s16),
                  child: Text(
                    'Compare with an earlier scan',
                    style: CruType.callout.tint(c.label),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final f in siblings)
                        ListTile(
                          title: Text(
                            p.basename(f.path),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: CruType.callout.tint(c.label),
                          ),
                          subtitle: Text(
                            '${ScanViewerPlaceholderScreen.formatBytes(f.lengthSync())}  ·  '
                            '${DateFormat('d MMM yyyy').format(f.statSync().modified)}',
                            style: CruType.caption.tint(c.label2),
                          ),
                          onTap: () => Navigator.of(ctx).pop(f.path),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(CruSpace.s16),
                  child: CruButton(
                    label: 'Browse files…',
                    kind: CruButtonKind.secondary,
                    onPressed: () async {
                      final picked = await _browseScan();
                      if (ctx.mounted) Navigator.of(ctx).pop(picked);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (chosen == null) return null;
    _comparePath = chosen;
    return {
      'fmt': p.extension(chosen).replaceFirst('.', '').toLowerCase(),
      'name': p.basename(chosen),
    };
  }

  Future<String?> _browseScan() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['stl', 'ply', 'obj'],
      dialogTitle: 'Select the scan to compare with',
    );
    if (result == null || result.files.isEmpty) return null;
    return result.files.single.path;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cru;
    final file = File(widget.filePath);
    final exists = file.existsSync();
    final ext = p.extension(widget.filePath).replaceFirst('.', '').toUpperCase();
    final isStl = ext == 'STL';
    final triangles =
        isStl && exists ? ScanViewerPlaceholderScreen.countStlTriangles(file) : null;
    final caption = [
      if (ext.isNotEmpty) ext,
      if (exists) ScanViewerPlaceholderScreen.formatBytes(file.lengthSync()),
      if (triangles != null) '${NumberFormat('#,###').format(triangles)} triangles',
    ].join('  ·  ');

    Widget view;
    if (_error != null) {
      view = Center(
        child: Text(_error!, style: CruType.callout.tint(c.label2)),
      );
    } else if (_url == null) {
      view = const Center(child: CircularProgressIndicator());
    } else {
      view = ClipRRect(
        borderRadius: BorderRadius.circular(CruRadius.control),
        child: InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri.uri(_url!)),
          initialSettings: InAppWebViewSettings(
            disableContextMenu: true,
            isInspectable: kDebugMode,
            supportZoom: false,
            disallowOverScroll: true,
            overScrollMode: OverScrollMode.NEVER,
          ),
          onWebViewCreated: (controller) {
            controller.addJavaScriptHandler(
              handlerName: 'pickCompare',
              callback: (_) => _pickCompare(),
            );
          },
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          },
          onConsoleMessage: kDebugMode
              ? (_, m) => debugPrint('[scan web] ${m.message}')
              : null,
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DentalPageHeader(
            title: widget.fileName.isNotEmpty ? widget.fileName : '3D Scan',
            subtitle: 'Optical scan file for CAD/CAM dental fabrication',
            actions: [
              CruButton(
                label: 'Close',
                kind: CruButtonKind.secondary,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: CruSpace.s8),
              CruButton(
                label: 'Open with default app',
                icon: CruIcons.arrowUpRight,
                kind: CruButtonKind.primary,
                onPressed: () => launchUrl(Uri.file(widget.filePath)),
              ),
            ],
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                CruSpace.s16,
                CruSpace.s8,
                CruSpace.s16,
                CruSpace.s8,
              ),
              child: view,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: CruSpace.s12),
            child: Text(
              caption,
              textAlign: TextAlign.center,
              style: CruType.caption.tint(c.label2),
            ),
          ),
        ],
      ),
    );
  }
}
