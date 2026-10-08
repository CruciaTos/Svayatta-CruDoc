import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/domain/files_builder.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';

const me = 'doc-a';
const colleague = 'doc-b';
final now = DateTime(2026, 10, 8, 12);

FileFolder folder(
  String id, {
  String parentId = '',
  String? rootId,
  String owner = me,
  FolderSharing sharing = FolderSharing.private,
  List<String>? visibleTo,
}) => FileFolder(
  id: id,
  doctorId: 'clinic',
  ownerUid: owner,
  parentId: parentId,
  rootId: rootId ?? id,
  name: id.toUpperCase(),
  sharing: sharing,
  visibleTo: visibleTo ?? [owner],
  createdAt: now,
  updatedAt: now,
);

PatientFile file(
  String id, {
  String patientId = 'p1',
  String folderId = '',
  String rootId = '',
  String owner = me,
  String name = 'scan.jpg',
  String contentType = 'image/jpeg',
  int daysAgo = 0,
  int size = 1000,
}) => PatientFile(
  id: id,
  doctorId: 'clinic',
  ownerUid: owner,
  patientId: patientId,
  folderId: folderId,
  rootId: rootId,
  name: name,
  contentType: contentType,
  sizeBytes: size,
  visibleTo: const [me],
  createdAt: now.subtract(Duration(days: daysAgo)),
  updatedAt: now,
);

FilesView build({
  List<FileFolder> folders = const [],
  required List<PatientFile> files,
  FilesTab tab = FilesTab.recent,
  String folderId = '',
  FileKind? filter,
  FilesSort sort = FilesSort.newest,
  String query = '',
  String? patientId,
  bool isAdmin = false,
}) => FilesBuilder.view(
  folders: folders,
  files: files,
  patientNames: const {'p1': 'Asha Rao', 'p2': 'Vikram Shah'},
  memberNames: const {colleague: 'Dr Mehta'},
  uid: me,
  isAdmin: isAdmin,
  now: now,
  tab: tab,
  folderId: folderId,
  filter: filter,
  sort: sort,
  query: query,
  patientId: patientId,
  selectedId: null,
);

void main() {
  group('Recent', () {
    test('lists every file newest first with its patient', () {
      final v = build(
        files: [
          file('old', daysAgo: 3),
          file('new', patientId: 'p2'),
          file('mid', daysAgo: 1),
        ],
      );
      expect(v.rows.map((e) => e.id), ['new', 'mid', 'old']);
      expect(v.rows.first.patientName, 'Vikram Shah');
      expect(v.selected?.id, 'new');
    });

    test('searches by patient name, file name and folder', () {
      final folders = [folder('xr')];
      final files = [
        file('a', name: 'opg.jpg'),
        file('b', patientId: 'p2', name: 'report.pdf'),
        file('c', name: 'bitewing.png', folderId: 'xr', rootId: 'xr'),
      ];
      expect(
        build(
          folders: folders,
          files: files,
          query: 'vikram',
        ).rows.map((e) => e.id),
        ['b'],
      );
      expect(
        build(
          folders: folders,
          files: files,
          query: 'OPG',
        ).rows.map((e) => e.id),
        ['a'],
      );
      expect(
        build(
          folders: folders,
          files: files,
          query: 'xr',
        ).rows.map((e) => e.id),
        ['c'],
      );
    });

    test('limits to one patient ("See all")', () {
      final v = build(
        files: [
          file('a'),
          file('b', patientId: 'p2'),
        ],
        patientId: 'p2',
      );
      expect(v.rows.map((e) => e.id), ['b']);
      expect(v.patientFilterName, 'Vikram Shah');
    });

    test('a patient this person cannot see shows as unknown', () {
      final v = build(files: [file('a', patientId: 'gone')]);
      expect(v.rows.single.patientName, 'Unknown patient');
    });

    test('kind chips count what the other choices leave, and filter', () {
      final files = [
        file('img'),
        file('pdf', name: 'r.pdf', contentType: 'application/pdf'),
        file('dcm', name: 'a.dcm', contentType: PatientFileTypes.dicom),
      ];
      final v = build(files: files, filter: FileKind.pdf);
      expect(v.rows.map((e) => e.id), ['pdf']);
      expect(
        {for (final c in v.chips) c.label: c.count},
        {'All': 3, 'Images': 1, 'PDFs': 1, 'Scans': 1},
      );
    });

    test('sorts by size and by patient', () {
      final files = [
        file('small', size: 10),
        file('big', size: 999, patientId: 'p2'),
      ];
      expect(build(files: files, sort: FilesSort.size).rows.first.id, 'big');
      expect(
        build(files: files, sort: FilesSort.patient).rows.first.id,
        'small', // Asha before Vikram
      );
    });
  });

  group('Folders', () {
    final folders = [
      folder('xr'),
      folder('y2026', parentId: 'xr', rootId: 'xr'),
      folder(
        'shared',
        owner: colleague,
        sharing: FolderSharing.team,
        visibleTo: const [colleague, kFilesTeam],
      ),
    ];
    final files = [
      file('loose'),
      file('in-xr', folderId: 'xr', rootId: 'xr'),
      file('deep', folderId: 'y2026', rootId: 'xr'),
      file('theirs', folderId: 'shared', rootId: 'shared', owner: colleague),
    ];

    test('the top shows top-level folders and loose files', () {
      final v = build(folders: folders, files: files, tab: FilesTab.folders);
      expect(v.folders.map((f) => f.id), ['shared', 'xr']);
      expect(v.rows.map((e) => e.id), ['loose']);
      expect(v.current, isNull);
    });

    test('a folder shows its folders and files, with breadcrumbs', () {
      final v = build(
        folders: folders,
        files: files,
        tab: FilesTab.folders,
        folderId: 'xr',
      );
      expect(v.folders.map((f) => f.id), ['y2026']);
      expect(v.rows.map((e) => e.id), ['in-xr']);
      expect(v.breadcrumbs.map((b) => b.id), ['xr']);
      expect(v.current?.files, 1);
      expect(v.current?.folders, 1);
    });

    test('searching inside a folder looks in its folders too', () {
      final v = build(
        folders: folders,
        files: files,
        tab: FilesTab.folders,
        folderId: 'xr',
        query: 'scan',
      );
      expect(v.rows.map((e) => e.id).toSet(), {'in-xr', 'deep'});
      expect(v.folders, isEmpty);
    });

    test('a shared folder names its owner; only its owner manages it', () {
      final v = build(folders: folders, files: files, tab: FilesTab.folders);
      final shared = v.folders.firstWhere((f) => f.id == 'shared');
      expect(shared.ownerName, 'Dr Mehta');
      expect(shared.canManage, isFalse);
      final theirs = build(
        folders: folders,
        files: files,
        tab: FilesTab.folders,
        folderId: 'shared',
      ).rows.single;
      expect(theirs.canManage, isFalse);
      expect(theirs.addedBy, 'Dr Mehta');
    });

    test('a clinic admin manages everything they can see', () {
      final theirs = build(
        folders: folders,
        files: files,
        tab: FilesTab.folders,
        folderId: 'shared',
        isAdmin: true,
      ).rows.single;
      expect(theirs.canManage, isTrue);
    });

    test('paths read top-level first', () {
      final v = build(folders: folders, files: files);
      expect(v.rows.firstWhere((e) => e.id == 'deep').folderPath, 'XR / Y2026');
    });
  });

  group('sharing', () {
    test('visibility per sharing choice', () {
      expect(FileFolder.visibilityFor(me, FolderSharing.private, const []), [
        me,
      ]);
      expect(FileFolder.visibilityFor(me, FolderSharing.team, const []), [
        me,
        kFilesTeam,
      ]);
      expect(
        FileFolder.visibilityFor(me, FolderSharing.people, const [
          colleague,
          me,
          kFilesTeam,
        ]),
        [me, colleague],
      );
    });
  });

  group('file types', () {
    test('maps extensions and refuses programs', () {
      expect(PatientFileTypes.contentTypeFor('OPG.JPG'), 'image/jpeg');
      expect(
        PatientFileTypes.contentTypeFor('study.dcm'),
        PatientFileTypes.dicom,
      );
      expect(PatientFileTypes.contentTypeFor('scan.stl'), 'model/stl');
      expect(PatientFileTypes.contentTypeFor('setup.exe'), isNull);
      expect(PatientFileTypes.contentTypeFor('archive.zip'), isNull);
      expect(PatientFileTypes.contentTypeFor('noextension'), isNull);
    });

    test('limits: 50 MB, 250 MB for DICOM and TIFF', () {
      expect(PatientFileTypes.maxBytesFor('image/jpeg'), 50 * 1024 * 1024);
      expect(
        PatientFileTypes.maxBytesFor(PatientFileTypes.dicom),
        250 * 1024 * 1024,
      );
    });

    test('storage.rules takes exactly the types the app uploads', () {
      final rules = File('storage.rules').readAsStringSync();
      final block = RegExp(
        r'match /patient-files/[\s\S]*?request\.resource\.contentType in \[([\s\S]*?)\]',
      ).firstMatch(rules);
      expect(block, isNotNull, reason: 'patient-files content types');
      final inRules = RegExp(
        r"'([^']+)'",
      ).allMatches(block!.group(1)!).map((m) => m.group(1)!).toSet();
      expect(inRules, PatientFileTypes.contentTypes);
    });
  });

  test('dates read like the rest of the app', () {
    expect(FilesBuilder.dateLabel(now, now), 'Today');
    expect(
      FilesBuilder.dateLabel(now.subtract(const Duration(days: 1)), now),
      'Yesterday',
    );
    expect(FilesBuilder.dateLabel(DateTime(2026, 3, 12), now), '12 Mar');
    expect(FilesBuilder.dateLabel(DateTime(2025, 3, 12), now), '12 Mar 2025');
  });
}
