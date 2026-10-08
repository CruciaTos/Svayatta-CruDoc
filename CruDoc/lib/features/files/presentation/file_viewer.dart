import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Desktop: files can also be handed to the computer's own apps.
bool get filesOnDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// A picture or PDF opened inside CruDoc, full screen. Esc closes it.
class FileViewerPage extends StatelessWidget {
  const FileViewerPage({
    super.key,
    required this.file,
    required this.local,
    required this.patientName,
  });

  final PatientFile file;
  final File local;
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
                          onPressed: () => launchUrl(Uri.file(local.path)),
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

  Widget _image(BuildContext context) {
    final c = context.cru;
    return InteractiveViewer(
      maxScale: 8,
      child: Center(
        child: Image.file(
          local,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Text(
            "This picture can't be shown here.",
            style: CruType.text.tint(c.label2),
          ),
        ),
      ),
    );
  }

  Widget _pdf(BuildContext context) {
    final c = context.cru;
    return PdfPreview(
      build: (_) => local.readAsBytes(),
      pdfFileName: file.name,
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      allowPrinting: true,
      allowSharing: true,
      useActions: true,
      onError: (context, error) => Center(
        child: Text(
          "This PDF can't be shown here.",
          style: CruType.text.tint(c.label2),
        ),
      ),
    );
  }
}
