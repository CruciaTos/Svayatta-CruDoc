import 'package:flutter/material.dart';

import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/presentation/files_actions.dart';
import 'package:doctor_management_app/features/files/presentation/widgets/progressive_picture.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// The handwritten pages a session note was read from, as thumbnails.
/// A tap opens the page full screen. Hidden when none are left.
class SessionScanCard extends StatefulWidget {
  const SessionScanCard({
    super.key,
    required this.fileIds,
    required this.patientName,
  });

  final List<String> fileIds;
  final String patientName;

  @override
  State<SessionScanCard> createState() => _SessionScanCardState();
}

class _SessionScanCardState extends State<SessionScanCard> {
  late final Future<List<PatientFile>> _filesFuture;

  @override
  void initState() {
    super.initState();
    _filesFuture = _loadFiles();
  }

  Future<List<PatientFile>> _loadFiles() async {
    final files = await Future.wait(
      widget.fileIds.map(FilesRepository.instance.file),
    );
    return [
      for (final f in files)
        if (f != null && !f.isDeleted) f,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<PatientFile>>(
      future: _filesFuture,
      builder: (context, snapshot) {
        final files = snapshot.data;
        if (files == null || files.isEmpty) {
          return const SizedBox.shrink();
        }
        final c = context.cru;
        return CruCard(
          padding: const EdgeInsets.all(CruSpace.s20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'SCANNED PAGES',
                style: CruType.groupLabel.tint(c.label2),
              ),
              const SizedBox(height: CruSpace.s12),
              Wrap(
                spacing: CruSpace.s10,
                runSpacing: CruSpace.s10,
                children: [
                  for (var i = 0; i < files.length; i++) ...[
                    () {
                      final file = files[i];
                      final thumb = fileThumbBytes(file);
                      return CruPressable(
                        semanticLabel: 'Open page ${i + 1}',
                        onTap: () => FilesActions.open(
                          context,
                          file,
                          patientName: widget.patientName,
                        ),
                        builder: (context, hovered) => ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 72,
                            height: 96,
                            child: thumb != null
                                ? Image.memory(thumb, fit: BoxFit.cover)
                                : ColoredBox(
                                    color: c.inset,
                                    child: Center(
                                      child: CruIcon(
                                        CruIcons.fileText,
                                        color: c.label3,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      );
                    }(),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
