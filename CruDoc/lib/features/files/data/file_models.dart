import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:doctor_management_app/features/files/data/file_types.dart';

/// Marks a folder or file as visible to everyone in the clinic who may see
/// clinical records. Stored in `visibleTo` next to person ids.
const String kFilesTeam = 'team';

/// Who a top-level folder is shared with. Folders inside it, and every
/// file in them, follow it.
enum FolderSharing {
  /// Only the person who made it.
  private('Only me'),

  /// Everyone in the clinic who may see clinical records.
  team('Everyone in the clinic'),

  /// The owner and the doctors they chose.
  people('Chosen doctors');

  const FolderSharing(this.label);
  final String label;

  static FolderSharing fromName(Object? name) => values.firstWhere(
    (s) => s.name == name,
    orElse: () => FolderSharing.private,
  );
}

/// Why a file stays on this computer only.
abstract final class FileCloudStatus {
  /// Uploaded, or waiting in the upload queue.
  static const none = '';

  /// The upload queue refused it (it is kept here so nothing is lost).
  static const localOnly = 'localOnly';
}

List<String> _decodeList(Object? raw) {
  if (raw is List) return [for (final e in raw) '$e'];
  if (raw is String && raw.isNotEmpty) {
    try {
      final d = jsonDecode(raw);
      if (d is List) return [for (final e in d) '$e'];
    } catch (_) {}
  }
  return const [];
}

/// A folder in someone's file tree. A folder with no parent is top-level:
/// its [rootId] is its own id and it carries the sharing. Folders inside it
/// copy its [visibleTo] and point [rootId] at it.
@immutable
class FileFolder {
  const FileFolder({
    required this.id,
    required this.doctorId,
    required this.ownerUid,
    required this.parentId,
    required this.rootId,
    required this.name,
    required this.sharing,
    required this.visibleTo,
    required this.createdAt,
    required this.updatedAt,
    this.isDeleted = false,
  });

  final String id;

  /// The clinic.
  final String doctorId;

  /// Who made it.
  final String ownerUid;

  /// '' for a top-level folder.
  final String parentId;

  /// The top-level folder this one is in (its own id when top-level).
  final String rootId;
  final String name;

  /// Meaningful on top-level folders; inner folders keep their root's.
  final FolderSharing sharing;

  /// Person ids, and [kFilesTeam] when shared with the clinic.
  final List<String> visibleTo;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isDeleted;

  bool get isTopLevel => parentId.isEmpty;

  bool get isShared => sharing != FolderSharing.private;

  /// The doctors a [FolderSharing.people] folder is shared with.
  List<String> get sharedWith => [
    for (final u in visibleTo)
      if (u != ownerUid && u != kFilesTeam) u,
  ];

  FileFolder copyWith({
    String? parentId,
    String? rootId,
    String? name,
    FolderSharing? sharing,
    List<String>? visibleTo,
    DateTime? updatedAt,
    bool? isDeleted,
  }) => FileFolder(
    id: id,
    doctorId: doctorId,
    ownerUid: ownerUid,
    parentId: parentId ?? this.parentId,
    rootId: rootId ?? this.rootId,
    name: name ?? this.name,
    sharing: sharing ?? this.sharing,
    visibleTo: visibleTo ?? this.visibleTo,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    isDeleted: isDeleted ?? this.isDeleted,
  );

  Map<String, Object?> toLocalMap() => {
    'id': id,
    'doctorId': doctorId,
    'ownerUid': ownerUid,
    'parentId': parentId,
    'rootId': rootId,
    'name': name,
    'sharing': sharing.name,
    'visibleTo': jsonEncode(visibleTo),
    'isDeleted': isDeleted ? 1 : 0,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory FileFolder.fromLocalMap(Map<String, Object?> m) => FileFolder(
    id: m['id'] as String? ?? '',
    doctorId: m['doctorId'] as String? ?? '',
    ownerUid: m['ownerUid'] as String? ?? '',
    parentId: m['parentId'] as String? ?? '',
    rootId: m['rootId'] as String? ?? '',
    name: m['name'] as String? ?? '',
    sharing: FolderSharing.fromName(m['sharing']),
    visibleTo: _decodeList(m['visibleTo']),
    isDeleted: (m['isDeleted'] as int? ?? 0) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int? ?? 0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int? ?? 0),
  );

  /// The visibility of a top-level folder shared as [sharing].
  static List<String> visibilityFor(
    String ownerUid,
    FolderSharing sharing,
    Iterable<String> people,
  ) => switch (sharing) {
    FolderSharing.private => [ownerUid],
    FolderSharing.team => [ownerUid, kFilesTeam],
    FolderSharing.people => [
      ownerUid,
      for (final u in people.toSet())
        if (u != ownerUid && u.isNotEmpty && u != kFilesTeam) u,
    ],
  };
}

/// One stored file. It always belongs to a patient.
@immutable
class PatientFile {
  const PatientFile({
    required this.id,
    required this.doctorId,
    required this.ownerUid,
    required this.patientId,
    required this.folderId,
    required this.rootId,
    required this.name,
    required this.contentType,
    required this.sizeBytes,
    required this.visibleTo,
    required this.createdAt,
    required this.updatedAt,
    this.localPath = '',
    this.storagePath = '',
    this.cloudStatus = FileCloudStatus.none,
    this.isDeleted = false,
  });

  final String id;
  final String doctorId;

  /// Who added it.
  final String ownerUid;
  final String patientId;

  /// '' when it isn't in a folder (then only its owner sees it).
  final String folderId;

  /// Its folder's top-level folder ('' when not in a folder).
  final String rootId;

  /// The name shown, with its extension ("OPG 12 Mar.jpg").
  final String name;
  final String contentType;
  final int sizeBytes;
  final List<String> visibleTo;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Where this device keeps a copy, relative to the files folder; '' when
  /// it hasn't been downloaded here.
  final String localPath;

  /// The object in Cloud Storage; '' until uploaded.
  final String storagePath;
  final String cloudStatus;
  final bool isDeleted;

  FileKind get kind => PatientFileTypes.kindOf(contentType);

  PatientFile copyWith({
    String? patientId,
    String? folderId,
    String? rootId,
    String? name,
    List<String>? visibleTo,
    DateTime? updatedAt,
    String? localPath,
    String? storagePath,
    String? cloudStatus,
    bool? isDeleted,
  }) => PatientFile(
    id: id,
    doctorId: doctorId,
    ownerUid: ownerUid,
    patientId: patientId ?? this.patientId,
    folderId: folderId ?? this.folderId,
    rootId: rootId ?? this.rootId,
    name: name ?? this.name,
    contentType: contentType,
    sizeBytes: sizeBytes,
    visibleTo: visibleTo ?? this.visibleTo,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    localPath: localPath ?? this.localPath,
    storagePath: storagePath ?? this.storagePath,
    cloudStatus: cloudStatus ?? this.cloudStatus,
    isDeleted: isDeleted ?? this.isDeleted,
  );

  Map<String, Object?> toLocalMap() => {
    'id': id,
    'doctorId': doctorId,
    'ownerUid': ownerUid,
    'patientId': patientId,
    'folderId': folderId,
    'rootId': rootId,
    'name': name,
    'contentType': contentType,
    'sizeBytes': sizeBytes,
    'visibleTo': jsonEncode(visibleTo),
    'localPath': localPath,
    'storagePath': storagePath,
    'cloudStatus': cloudStatus,
    'isDeleted': isDeleted ? 1 : 0,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory PatientFile.fromLocalMap(Map<String, Object?> m) => PatientFile(
    id: m['id'] as String? ?? '',
    doctorId: m['doctorId'] as String? ?? '',
    ownerUid: m['ownerUid'] as String? ?? '',
    patientId: m['patientId'] as String? ?? '',
    folderId: m['folderId'] as String? ?? '',
    rootId: m['rootId'] as String? ?? '',
    name: m['name'] as String? ?? '',
    contentType: m['contentType'] as String? ?? '',
    sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
    visibleTo: _decodeList(m['visibleTo']),
    localPath: m['localPath'] as String? ?? '',
    storagePath: m['storagePath'] as String? ?? '',
    cloudStatus: m['cloudStatus'] as String? ?? '',
    isDeleted: (m['isDeleted'] as int? ?? 0) == 1,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int? ?? 0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int? ?? 0),
  );
}

/// Whether [uid] may see something visible to [visibleTo].
bool filesVisibleTo(List<String> visibleTo, String uid) =>
    visibleTo.contains(kFilesTeam) || visibleTo.contains(uid);
