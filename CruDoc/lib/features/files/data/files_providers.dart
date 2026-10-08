import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:doctor_management_app/core/clinic/clinic_permission.dart';
import 'package:doctor_management_app/core/clinic/clinic_session.dart';
import 'package:doctor_management_app/core/services/auth_providers.dart';
import 'package:doctor_management_app/features/dashboard/data/providers/dashboard_providers.dart';
import 'package:doctor_management_app/features/files/data/file_models.dart';
import 'package:doctor_management_app/features/files/data/file_types.dart';
import 'package:doctor_management_app/features/files/data/files_repository.dart';
import 'package:doctor_management_app/features/files/domain/files_builder.dart';
import 'package:doctor_management_app/features/files/domain/files_models.dart';
import 'package:doctor_management_app/features/patients/data/providers/patient_providers.dart';
import 'package:doctor_management_app/features/team/data/team_providers.dart';

/// Bumps whenever a file or folder changes (here or synced).
final filesVersionProvider = StreamProvider<int>((ref) async* {
  yield 0;
  var version = 0;
  await for (final _ in FilesRepository.changes) {
    yield ++version;
  }
});

/// Every folder and file this person can see.
final filesDataProvider =
    FutureProvider<({List<FileFolder> folders, List<PatientFile> files})>((
      ref,
    ) async {
      ref.watch(filesVersionProvider);
      ref.watch(authStateProvider);
      ref.watch(clinicAccessProvider);
      final repo = FilesRepository.instance;
      final folders = await repo.folders();
      final files = await repo.files();
      return (folders: folders, files: files);
    });

/// A patient's files, newest first (the patient screen's Files card).
final patientFilesProvider = FutureProvider.family<List<PatientFile>, String>((
  ref,
  patientId,
) {
  ref.watch(filesVersionProvider);
  ref.watch(clinicAccessProvider);
  return FilesRepository.instance.files(patientId: patientId);
});

/// The signed-in person, as the Files rules see them. Tests override it.
final filesUidProvider = Provider<String>((ref) {
  ref.watch(authStateProvider);
  ref.watch(clinicAccessProvider);
  return FilesRepository.instance.uid;
});

/// Patient names by id, for the list.
final _patientNamesProvider = Provider<Map<String, String>>((ref) {
  final patients = ref.watch(patientsStreamProvider).value ?? const [];
  return {for (final p in patients) p.id: p.fullName.trim()};
});

/// Colleagues' names by uid ("Shared by Dr Rao").
final _memberNamesProvider = Provider<Map<String, String>>((ref) {
  final members = ref.watch(clinicMembersProvider).value ?? const [];
  return {for (final m in members) m.uid: m.name};
});

/// `shared_preferences` storage for the list/grid choice.
abstract final class _FilesViewPreferences {
  static const String _key = 'crudoc.files.viewMode';

  static Future<FilesViewMode> get() async {
    final prefs = await SharedPreferences.getInstance();
    return FilesViewMode.fromName(prefs.getString(_key));
  }

  static Future<void> set(FilesViewMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }
}

/// What the person has chosen on the Files screen.
@immutable
class FilesState {
  const FilesState({
    this.tab = FilesTab.recent,
    this.folderId = '',
    this.filter,
    this.sort = FilesSort.newest,
    this.query = '',
    this.patientId,
    this.selectedId,
    this.panelOpen = false,
    this.viewMode = FilesViewMode.list,
    this.limit = FilesBuilder.pageSize,
  });

  final FilesTab tab;

  /// The open folder on the Folders tab ('' at the top).
  final String folderId;

  /// The kind chip (null = All).
  final FileKind? filter;
  final FilesSort sort;
  final String query;

  /// Only this patient's files ("See all" on the patient screen).
  final String? patientId;

  /// Null: the panel shows the first file.
  final String? selectedId;

  /// Below 1200 px the panel is a sheet, open only after a selection.
  final bool panelOpen;
  final FilesViewMode viewMode;
  final int limit;

  FilesState copyWith({
    FilesTab? tab,
    String? folderId,
    FileKind? filter,
    bool clearFilter = false,
    FilesSort? sort,
    String? query,
    String? patientId,
    bool clearPatient = false,
    String? selectedId,
    bool clearSelected = false,
    bool? panelOpen,
    FilesViewMode? viewMode,
    int? limit,
  }) => FilesState(
    tab: tab ?? this.tab,
    folderId: folderId ?? this.folderId,
    filter: clearFilter ? null : (filter ?? this.filter),
    sort: sort ?? this.sort,
    query: query ?? this.query,
    patientId: clearPatient ? null : (patientId ?? this.patientId),
    selectedId: clearSelected ? null : (selectedId ?? this.selectedId),
    panelOpen: panelOpen ?? this.panelOpen,
    viewMode: viewMode ?? this.viewMode,
    limit: limit ?? this.limit,
  );
}

class FilesController extends Notifier<FilesState> {
  /// [initial] skips loading the stored view mode (tests).
  FilesController({this.initial});

  final FilesState? initial;

  @override
  FilesState build() {
    if (initial != null) return initial!;
    Future(() async {
      final stored = await _FilesViewPreferences.get();
      if (ref.mounted && stored != state.viewMode) {
        state = state.copyWith(viewMode: stored);
      }
    });
    return const FilesState();
  }

  FilesState _reset(FilesState s) => s.copyWith(
    limit: FilesBuilder.pageSize,
    clearSelected: true,
    panelOpen: false,
  );

  void setTab(FilesTab tab) {
    if (tab == state.tab) return;
    state = _reset(state.copyWith(tab: tab));
  }

  /// Opens a folder on the Folders tab ('' for the top).
  void openFolder(String folderId) => state = _reset(
    state.copyWith(tab: FilesTab.folders, folderId: folderId, query: ''),
  );

  void setFilter(FileKind? kind) =>
      state = _reset(state.copyWith(filter: kind, clearFilter: kind == null));

  void setSort(FilesSort sort) =>
      state = state.copyWith(sort: sort, limit: FilesBuilder.pageSize);

  void setQuery(String query) {
    if (query == state.query) return;
    state = _reset(state.copyWith(query: query));
  }

  /// Limits the list to one patient (null for everyone).
  void setPatient(String? patientId) => state = _reset(
    state.copyWith(patientId: patientId, clearPatient: patientId == null),
  );

  /// "See all" from a patient: their files, newest first.
  void showPatient(String patientId) => state = _reset(
    state.copyWith(
      tab: FilesTab.recent,
      patientId: patientId,
      query: '',
      clearFilter: true,
      sort: FilesSort.newest,
    ),
  );

  void select(String id) =>
      state = state.copyWith(selectedId: id, panelOpen: true);

  void closePanel() => state = state.copyWith(panelOpen: false);

  void showMore() =>
      state = state.copyWith(limit: state.limit + FilesBuilder.pageSize);

  Future<void> setViewMode(FilesViewMode mode) async {
    if (mode == state.viewMode) return;
    state = state.copyWith(viewMode: mode);
    await _FilesViewPreferences.set(mode);
  }
}

final filesControllerProvider = NotifierProvider<FilesController, FilesState>(
  FilesController.new,
);

/// Everything the Files screen shows.
final filesViewProvider = Provider<AsyncValue<FilesView>>((ref) {
  final data = ref.watch(filesDataProvider);
  final s = ref.watch(filesControllerProvider);
  final now = ref.watch(dashboardNowProvider);
  final names = ref.watch(_patientNamesProvider);
  final members = ref.watch(_memberNamesProvider);
  final access = ref.watch(clinicAccessProvider).value;

  final d = data.value;
  if (d == null) {
    if (data.hasError) {
      return AsyncError(data.error!, data.stackTrace ?? StackTrace.current);
    }
    return const AsyncLoading();
  }
  return AsyncData(
    FilesBuilder.view(
      folders: d.folders,
      files: d.files,
      patientNames: names,
      memberNames: members,
      uid: ref.watch(filesUidProvider),
      isAdmin: access?.isAdmin ?? true,
      canEdit: access?.can(ClinicPermission.clinicalEdit) ?? true,
      now: now,
      tab: s.tab,
      folderId: s.folderId,
      filter: s.filter,
      sort: s.sort,
      query: s.query,
      patientId: s.patientId,
      selectedId: s.selectedId,
      limit: s.limit,
    ),
  );
});
