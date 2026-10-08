import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';

/// Recent: every file, newest first. Folders: the folder tree, like a
/// computer's.
enum FilesTab {
  recent('Recent'),
  folders('Folders');

  const FilesTab(this.label);
  final String label;
}

/// List rows or grid tiles (with picture previews). Remembered per device.
enum FilesViewMode {
  list,
  grid;

  static FilesViewMode fromName(String? name) => FilesViewMode.values
      .firstWhere((m) => m.name == name, orElse: () => FilesViewMode.list);
}

enum FilesSort {
  newest('Newest first'),
  oldest('Oldest first'),
  name('Name'),
  patient('Patient'),
  size('Size');

  const FilesSort(this.label);
  final String label;
}

/// One filter chip: All (null kind) or a kind of file, with its count.
@immutable
class FilesChip {
  const FilesChip(this.kind, this.count);

  /// Null for All.
  final FileKind? kind;
  final int count;

  String get label => kind?.label ?? 'All';
}

/// A file with what the list shows next to it.
@immutable
class FileEntry {
  const FileEntry({
    required this.file,
    required this.patientName,
    required this.folderPath,
    required this.addedBy,
    required this.canManage,
  });

  final PatientFile file;

  /// "Unknown patient" when this person can't see the patient.
  final String patientName;

  /// "X-rays / 2026", '' when not in a folder.
  final String folderPath;

  /// Who added it; '' when it was this person.
  final String addedBy;
  final bool canManage;

  String get id => file.id;
}

/// A folder with what its row shows.
@immutable
class FolderEntry {
  const FolderEntry({
    required this.folder,
    required this.files,
    required this.folders,
    required this.ownerName,
    required this.canManage,
  });

  final FileFolder folder;

  /// Files directly inside (not in its folders).
  final int files;

  /// Folders directly inside.
  final int folders;

  /// Who made it, when it is someone else's ('' for this person's own).
  final String ownerName;
  final bool canManage;

  String get id => folder.id;
}

/// Everything the Files screen shows for the current choices.
@immutable
class FilesView {
  const FilesView({
    required this.now,
    required this.totalFiles,
    required this.totalFolders,
    required this.folders,
    required this.rows,
    required this.visible,
    required this.chips,
    required this.filter,
    required this.sort,
    required this.breadcrumbs,
    required this.current,
    required this.selected,
    required this.selectedExplicit,
    required this.patientFilterName,
    required this.allFolders,
  });

  final DateTime now;

  /// Every file and folder this person can see.
  final int totalFiles;
  final int totalFolders;

  /// Folders shown above the files (Folders tab, no search).
  final List<FolderEntry> folders;

  /// Files after filters, search and sort.
  final List<FileEntry> rows;

  /// The first page of [rows].
  final List<FileEntry> visible;
  final List<FilesChip> chips;

  /// The kind chip applied (null = All).
  final FileKind? filter;
  final FilesSort sort;

  /// Top-level folder … current folder (Folders tab).
  final List<FolderEntry> breadcrumbs;

  /// The open folder (Folders tab), null at the top.
  final FolderEntry? current;

  /// The file the panel shows: the chosen one, else the first row.
  final FileEntry? selected;

  /// True when [selected] was chosen (not the first row by default).
  final bool selectedExplicit;

  /// The patient the list is limited to, if any.
  final String? patientFilterName;

  /// Every folder this person can see (move targets, names).
  final List<FolderEntry> allFolders;

  bool get isEmpty => totalFiles == 0 && totalFolders == 0;
}
