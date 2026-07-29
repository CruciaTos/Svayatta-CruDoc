import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/doctor_model.dart';
import '../config/enums.dart';
import '../services/doctor_service.dart';

/// State for doctor management.
class DoctorListState {
  final List<DoctorModel> doctors;
  final bool isLoading;
  final String? errorMessage;
  final String? searchQuery;
  final DoctorStatus? statusFilter;
  final SubscriptionPlan? planFilter;
  final String? lastDocId;
  final bool hasMore;

  const DoctorListState({
    this.doctors = const [],
    this.isLoading = false,
    this.errorMessage,
    this.searchQuery,
    this.statusFilter,
    this.planFilter,
    this.lastDocId,
    this.hasMore = true,
  });

  DoctorListState copyWith({
    List<DoctorModel>? doctors,
    bool? isLoading,
    String? errorMessage,
    String? searchQuery,
    DoctorStatus? statusFilter,
    SubscriptionPlan? planFilter,
    String? lastDocId,
    bool? hasMore,
    bool clearError = false,
  }) {
    return DoctorListState(
      doctors: doctors ?? this.doctors,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      searchQuery: searchQuery ?? this.searchQuery,
      statusFilter: statusFilter ?? this.statusFilter,
      planFilter: planFilter ?? this.planFilter,
      lastDocId: lastDocId ?? this.lastDocId,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

/// Provider for doctor list management.
class DoctorListNotifier extends Notifier<DoctorListState> {
  late final SuperAdminDoctorService _service;

  @override
  DoctorListState build() {
    _service = SuperAdminDoctorService();
    return const DoctorListState();
  }

  Future<void> loadDoctors({bool refresh = false}) async {
    if (refresh) {
      state = state.copyWith(isLoading: true, doctors: [], lastDocId: null, hasMore: true);
    } else {
      state = state.copyWith(isLoading: true);
    }

    try {
      final result = await _service.getAllDoctors(
        limit: 50,
        lastDocId: refresh ? null : state.lastDocId,
        searchQuery: state.searchQuery,
        statusFilter: state.statusFilter,
        planFilter: state.planFilter,
      );

      state = state.copyWith(
        doctors: refresh ? result : [...state.doctors, ...result],
        isLoading: false,
        lastDocId: result.isNotEmpty ? result.last.id : state.lastDocId,
        hasMore: result.length >= 50,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
    loadDoctors(refresh: true);
  }

  void setStatusFilter(DoctorStatus? status) {
    state = state.copyWith(statusFilter: status);
    loadDoctors(refresh: true);
  }

  void setPlanFilter(SubscriptionPlan? plan) {
    state = state.copyWith(planFilter: plan);
    loadDoctors(refresh: true);
  }
}

final doctorListProvider = NotifierProvider<DoctorListNotifier, DoctorListState>(
  DoctorListNotifier.new,
);