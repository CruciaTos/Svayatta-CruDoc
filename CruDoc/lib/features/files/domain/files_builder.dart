import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';

/// Builds [FilesView] from records. Pure: no IO, so tests can drive it.
abstract final class FilesBuilder {
  /// Rows revealed at a time.
  static const int pageSize = 60;

  static FilesView view({
    required List<FileFolder> folders,
    required List<PatientFile> files,
    required Map<String, String> patientNames,
    required Map<String, String> memberNames,
    required String uid,
    required bool isAdmin,
    required DateTime now,
    bool canEdit = true,
    required FilesTab tab,
    required String folderId,
    required FileKind? filter,
    required FilesSort sort,
    required String query,
    required String? patientId,
    required String? selectedId,
    int limit = pageSize,
  }) {
    final byId = {for (final f in folders) f.id: f};

    bool canManage(String ownerUid, String rootId) {
      if (!canEdit) return false;
      if (ownerUid == uid || isAdmin) return true;
      final root = byId[rootId];
      return root != null && root.ownerUid == uid;
    }

    String nameOf(String memberUid) =>
        memberUid == uid ? '' : (memberNames[memberUid] ?? 'A colleague');

    // Folders by parent, and direct file counts.
    final childFolders = <String, int>{};
    for (final f in folders) {
      childFolders[f.parentId] = (childFolders[f.parentId] ?? 0) + 1;
    }
    final directFiles = <String, int>{};
    for (final f in files) {
      directFiles[f.folderId] = (directFiles[f.folderId] ?? 0) + 1;
    }
    FolderEntry entryOf(FileFolder f) => FolderEntry(
      folder: f,
      files: directFiles[f.id] ?? 0,
      folders: childFolders[f.id] ?? 0,
      ownerName: nameOf(f.ownerUid),
      canManage: canManage(f.ownerUid, f.rootId),
    );

    // A folder whose parent this person can't see shows at the top.
    String parentOf(FileFolder f) =>
        byId.containsKey(f.parentId) ? f.parentId : '';

    String pathOf(String id) {
      final parts = <String>[];
      var cursor = byId[id];
      var guard = 0;
      while (cursor != null && guard++ < 64) {
        parts.insert(0, cursor.name);
        cursor = byId[cursor.parentId];
      }
      return parts.join(' / ');
    }

    // The open folder, if it still exists.
    final current = tab == FilesTab.folders ? byId[folderId] : null;
    final crumbs = <FolderEntry>[];
    {
      var cursor = current;
      var guard = 0;
      while (cursor != null && guard++ < 64) {
        crumbs.insert(0, entryOf(cursor));
        cursor = byId[cursor.parentId];
      }
    }

    // Folders tab: the open folder and everything below it.
    Set<String>? subtree;
    if (tab == FilesTab.folders && current != null) {
      subtree = {current.id};
      var grew = true;
      while (grew) {
        grew = false;
        for (final f in folders) {
          if (!subtree.contains(f.id) && subtree.contains(f.parentId)) {
            subtree.add(f.id);
            grew = true;
          }
        }
      }
    }

    final q = query.trim().toLowerCase();
    String patientName(String id) => patientNames[id] ?? 'Unknown patient';

    // Scope: tab, folder, patient and search (before the kind chip, so
    // the chips count what the other choices leave).
    final scoped = <PatientFile>[];
    for (final f in files) {
      if (patientId != null && f.patientId != patientId) continue;
      if (tab == FilesTab.folders) {
        if (q.isEmpty) {
          // Only what is directly in the open folder (or loose files at
          // the top).
          final where = byId.containsKey(f.folderId) ? f.folderId : '';
          if (where != (current?.id ?? '')) continue;
        } else if (subtree != null && !subtree.contains(f.folderId)) {
          continue;
        }
      }
      if (q.isNotEmpty) {
        final hay =
            '${f.name} ${patientName(f.patientId)} ${pathOf(f.folderId)}'
                .toLowerCase();
        if (!hay.contains(q)) continue;
      }
      scoped.add(f);
    }

    final counts = <FileKind, int>{};
    for (final f in scoped) {
      counts[f.kind] = (counts[f.kind] ?? 0) + 1;
    }
    final chips = [
      FilesChip(null, scoped.length),
      for (final k in FileKind.values)
        if ((counts[k] ?? 0) > 0) FilesChip(k, counts[k]!),
    ];
    final activeFilter = filter != null && (counts[filter] ?? 0) > 0
        ? filter
        : null;

    final entries = [
      for (final f in scoped)
        if (activeFilter == null || f.kind == activeFilter)
          FileEntry(
            file: f,
            patientName: patientName(f.patientId),
            folderPath: pathOf(f.folderId),
            addedBy: nameOf(f.ownerUid),
            canManage: canManage(f.ownerUid, f.rootId),
          ),
    ];
    int newest(FileEntry a, FileEntry b) =>
        b.file.createdAt.compareTo(a.file.createdAt);
    entries.sort(switch (sort) {
      FilesSort.newest => newest,
      FilesSort.oldest => (a, b) => newest(b, a),
      FilesSort.name => (a, b) {
        final c = a.file.name.toLowerCase().compareTo(
          b.file.name.toLowerCase(),
        );
        return c != 0 ? c : newest(a, b);
      },
      FilesSort.patient => (a, b) {
        final c = a.patientName.toLowerCase().compareTo(
          b.patientName.toLowerCase(),
        );
        return c != 0 ? c : newest(a, b);
      },
      FilesSort.size => (a, b) {
        final c = b.file.sizeBytes.compareTo(a.file.sizeBytes);
        return c != 0 ? c : newest(a, b);
      },
    });

    // Folders shown above the files: the open folder's own (Folders tab,
    // not searching), sorted by name.
    final shownFolders = <FolderEntry>[];
    if (tab == FilesTab.folders && q.isEmpty) {
      for (final f in folders) {
        if (parentOf(f) == (current?.id ?? '')) shownFolders.add(entryOf(f));
      }
      shownFolders.sort(
        (a, b) =>
            a.folder.name.toLowerCase().compareTo(b.folder.name.toLowerCase()),
      );
    }

    final visible = entries.take(limit).toList();
    FileEntry? selected;
    var explicit = false;
    if (selectedId != null) {
      for (final e in entries) {
        if (e.id == selectedId) {
          selected = e;
          explicit = true;
          break;
        }
      }
    }
    selected ??= entries.isEmpty ? null : entries.first;

    return FilesView(
      now: now,
      totalFiles: files.length,
      totalFolders: folders.length,
      folders: shownFolders,
      rows: entries,
      visible: visible,
      chips: chips,
      filter: activeFilter,
      sort: sort,
      breadcrumbs: crumbs,
      current: current == null ? null : entryOf(current),
      selected: selected,
      selectedExplicit: explicit,
      patientFilterName: patientId == null ? null : patientName(patientId),
      allFolders: [for (final f in folders) entryOf(f)]
        ..sort(
          (a, b) =>
              pathOf(a.id).toLowerCase().compareTo(pathOf(b.id).toLowerCase()),
        ),
    );
  }

  /// "X-rays / 2026" for [folderId] among [folders].
  static String pathOf(String folderId, List<FolderEntry> folders) {
    final byId = {for (final f in folders) f.id: f.folder};
    final parts = <String>[];
    var cursor = byId[folderId];
    var guard = 0;
    while (cursor != null && guard++ < 64) {
      parts.insert(0, cursor.name);
      cursor = byId[cursor.parentId];
    }
    return parts.join(' / ');
  }

  /// "Today", "Yesterday", "12 Mar", or "12 Mar 2025" in another year.
  static String dateLabel(DateTime d, DateTime now) {
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final base = '${d.day} ${months[d.month - 1]}';
    return d.year == now.year ? base : '$base ${d.year}';
  }

  static String typeLabel(PatientFile f) {
    final dot = f.name.lastIndexOf('.');
    final ext = dot >= 0 && dot < f.name.length - 1
        ? f.name.substring(dot + 1).toUpperCase()
        : '';
    final size = PatientFileTypes.sizeLabel(f.sizeBytes);
    return ext.isEmpty ? size : '$ext · $size';
  }
}
