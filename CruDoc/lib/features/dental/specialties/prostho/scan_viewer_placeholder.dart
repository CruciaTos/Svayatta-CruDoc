import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/dental/presentation/desktop/dental_ui.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Screen displayed when opening a 3D scan (.stl, .ply, .obj).
/// Shows scan metadata and triangle count without attempting in-app 3D rendering.
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

      final count = ByteData.sublistView(headerAndCount).getUint32(80, Endian.little);
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
  Widget build(BuildContext context) {
    final c = context.cru;
    final file = File(filePath);
    final exists = file.existsSync();
    final ext = p.extension(filePath).replaceFirst('.', '').toUpperCase();
    final fileSize = exists ? formatBytes(file.lengthSync()) : 'Unknown';
    final isStl = ext == 'STL';
    final triangles = isStl && exists ? countStlTriangles(file) : null;
    final formatter = NumberFormat('#,###');

    return Scaffold(
      backgroundColor: c.canvas,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          DentalPageHeader(
            title: fileName.isNotEmpty ? fileName : '3D Scan',
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
                onPressed: () => launchUrl(Uri.file(filePath)),
              ),
            ],
          ),

          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.all(CruSpace.s24),
                  child: CruCard(
                    padding: const EdgeInsets.all(CruSpace.s24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const CruIconTile(
                          icon: CruIcons.box,
                          tone: CruTileTone.accent,
                        ),
                        const SizedBox(height: CruSpace.s16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: CruType.title2.tint(c.label),
                              ),
                            ),
                            const SizedBox(width: CruSpace.s8),
                            CruPill(
                              text: ext.isNotEmpty ? ext : '3D',
                              background: c.accentTint,
                              foreground: c.accent,
                            ),
                          ],
                        ),
                        const SizedBox(height: CruSpace.s20),

                        // Scan metadata summary
                        Container(
                          padding: const EdgeInsets.all(CruSpace.s16),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(CruRadius.control),
                            border: Border.all(color: c.hairline),
                          ),
                          child: Column(
                            children: [
                              _metaRow('File type', '$ext 3D Mesh', c),
                              const CruSeparator(),
                              _metaRow('File size', fileSize, c),
                              if (triangles != null) ...[
                                const CruSeparator(),
                                _metaRow(
                                  'Triangles',
                                  '${formatter.format(triangles)} facets',
                                  c,
                                ),
                              ],
                              const CruSeparator(),
                              _metaRow('Status', exists ? 'Ready to open' : 'File not found on disk', c),
                            ],
                          ),
                        ),
                        const SizedBox(height: CruSpace.s20),

                        // Honest placeholder note
                        Container(
                          padding: const EdgeInsets.all(CruSpace.s12),
                          decoration: BoxDecoration(
                            color: c.inset,
                            borderRadius: BorderRadius.circular(CruRadius.control),
                          ),
                          child: Row(
                            children: [
                              CruIcon(CruIcons.help, size: 16, color: c.label2),
                              const SizedBox(width: CruSpace.s8),
                              Expanded(
                                child: Text(
                                  '3D view of scans isn\'t built yet. Open the file in your CAD or lab software.',
                                  style: CruType.caption.tint(c.label2),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: CruSpace.s24),

                        // Action button
                        CruButton(
                          label: 'Open with default app',
                          icon: CruIcons.arrowUpRight,
                          kind: CruButtonKind.primary,
                          onPressed: () => launchUrl(Uri.file(filePath)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value, CruColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: CruSpace.s6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: CruType.callout.tint(c.label2)),
          Text(value, style: CruType.callout.w600.tabular.tint(c.label)),
        ],
      ),
    );
  }
}
