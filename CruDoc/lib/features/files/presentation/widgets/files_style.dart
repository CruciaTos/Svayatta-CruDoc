import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/shared/widgets/cru/cru.dart';

/// Icons the Files screen needs that `CruIcons` doesn't have.
abstract final class FileIcons {
  static const folder = CruIconData(
    'M3.5 7.5a2 2 0 0 1 2-2h4l2 2.5h7a2 2 0 0 1 2 2v7.5a2 2 0 0 1-2 2h-13'
    'a2 2 0 0 1-2-2z',
  );

  static const folderPlus = CruIconData(
    'M3.5 7.5a2 2 0 0 1 2-2h4l2 2.5h7a2 2 0 0 1 2 2v7.5a2 2 0 0 1-2 2h-13'
    'a2 2 0 0 1-2-2zM12 11v5M9.5 13.5h5',
  );

  static const image = CruIconData(
    'M20.5 15.5l-4.5-4.5-8.5 8.5',
    rects: [(3.5, 4.5, 17, 15, 2.5)],
    circles: [(9, 9.5, 1.6)],
  );

  /// A cube: DICOM studies and 3D scans.
  static const scan = CruIconData(
    'M12 3.5l7.5 4.25v8.5L12 20.5l-7.5-4.25v-8.5zM12 12l7.5-4.25M12 12v8.5'
    'M12 12L4.5 7.75',
  );

  static const video = CruIconData(
    'M15.5 10.5l5-3v9l-5-3',
    rects: [(3.5, 6, 12, 12, 2.5)],
  );

  static const audio = CruIconData(
    'M9 17.5V6l10-2v11.5',
    circles: [(6.5, 17.5, 2.5), (16.5, 15.5, 2.5)],
  );

  static const upload = CruIconData(
    'M12 15.5v-11M7.5 9l4.5-4.5L16.5 9'
    'M4 15.5v2a3 3 0 0 0 3 3h10a3 3 0 0 0 3-3v-2',
  );

  static const trash = CruIconData(
    'M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 12.5h9l1-12.5',
  );

  /// Two people (shared folder).
  static const shared = CruIcons.patients;
}

CruIconData fileKindIcon(FileKind kind) => switch (kind) {
  FileKind.image => FileIcons.image,
  FileKind.scan => FileIcons.scan,
  FileKind.video => FileIcons.video,
  FileKind.audio => FileIcons.audio,
  FileKind.pdf || FileKind.document => CruIcons.fileText,
};

/// Sizes from the Inventory layout the Files screen follows.
abstract final class FilesSize {
  /// List columns: Patient, Folder (or Added by), Added. Name flexes.
  static const double patientColumn = 180;
  static const double folderColumn = 160;
  static const double dateColumn = 92;
  static const double columnGap = 20;

  /// Selection rings: list row and grid tile.
  static const double rowRing = 1.5;
  static const double tileRing = 2;

  /// Grid tiles: a preview above two lines of text.
  static const double tileHeight = 196;
  static const double tilePreview = 112;
  static const double tileRadius = 20;
  static const double tileGap = 14;

  /// Below this width the grid drops a column.
  static const double gridFourColumns = 860;
  static const double gridThreeColumns = 600;

  /// The preview in the panel.
  static const double panelPreview = 180;
}
