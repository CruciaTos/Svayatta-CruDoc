import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/enums.dart';

/// Represents a single feature module with its metadata for display.
class FeatureModuleItem {
  final FeatureModule module;
  final String description;
  final IconCategory iconCategory;
  final bool isGloballyEnabled;
  final bool isBeta;
  final int enabledDoctorsCount;
  final int totalDoctors;
  final Map<SubscriptionPlan, bool> planAvailability;
  final double? customMonthlyPrice;

  const FeatureModuleItem({
    required this.module,
    required this.description,
    required this.iconCategory,
    this.isGloballyEnabled = true,
    this.isBeta = false,
    this.enabledDoctorsCount = 0,
    this.totalDoctors = 0,
    this.planAvailability = const {},
    this.customMonthlyPrice,
  });

  double get monthlyPrice => customMonthlyPrice ?? module.defaultAddonPrice;

  FeatureModuleItem copyWith({
    bool? isGloballyEnabled,
    bool? isBeta,
    int? enabledDoctorsCount,
    double? customMonthlyPrice,
  }) {
    return FeatureModuleItem(
      module: module,
      description: description,
      iconCategory: iconCategory,
      isGloballyEnabled: isGloballyEnabled ?? this.isGloballyEnabled,
      isBeta: isBeta ?? this.isBeta,
      enabledDoctorsCount: enabledDoctorsCount ?? this.enabledDoctorsCount,
      totalDoctors: totalDoctors,
      planAvailability: planAvailability,
      customMonthlyPrice: customMonthlyPrice ?? this.customMonthlyPrice,
    );
  }

  double get adoptionPercentage =>
      totalDoctors > 0 ? (enabledDoctorsCount / totalDoctors) * 100 : 0;
}

/// Icon categories for grouping features visually.
enum IconCategory { core, clinical, financial, advanced }

/// State for Feature Management screen.
class FeatureManagementState {
  final List<FeatureModuleItem> features;
  final bool isLoading;
  final String? errorMessage;
  final String searchQuery;
  final IconCategory? categoryFilter;
  final bool? betaFilter;

  const FeatureManagementState({
    this.features = const [],
    this.isLoading = false,
    this.errorMessage,
    this.searchQuery = '',
    this.categoryFilter,
    this.betaFilter,
  });

  FeatureManagementState copyWith({
    List<FeatureModuleItem>? features,
    bool? isLoading,
    String? errorMessage,
    String? searchQuery,
    IconCategory? categoryFilter,
    bool? betaFilter,
    bool clearError = false,
    bool clearCategory = false,
    bool clearBeta = false,
  }) {
    return FeatureManagementState(
      features: features ?? this.features,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      searchQuery: searchQuery ?? this.searchQuery,
      categoryFilter:
          clearCategory ? null : (categoryFilter ?? this.categoryFilter),
      betaFilter: clearBeta ? null : (betaFilter ?? this.betaFilter),
    );
  }

  List<FeatureModuleItem> get filteredFeatures {
    return features.where((f) {
      if (searchQuery.isNotEmpty) {
        final q = searchQuery.toLowerCase().trim();
        if (!f.module.label.toLowerCase().contains(q) &&
            !f.description.toLowerCase().contains(q)) {
          return false;
        }
      }
      if (categoryFilter != null && f.iconCategory != categoryFilter) {
        return false;
      }
      if (betaFilter != null && f.isBeta != betaFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  int get totalEnabled => features.where((f) => f.isGloballyEnabled).length;
  int get totalBeta => features.where((f) => f.isBeta).length;
  int get totalDisabled => features.where((f) => !f.isGloballyEnabled).length;
}

/// Notifier for Feature Management state.
class FeatureManagementNotifier extends Notifier<FeatureManagementState> {
  @override
  FeatureManagementState build() {
    Future.microtask(() => loadFeatures());
    return const FeatureManagementState();
  }

  static const _totalDoctors = 48;

  List<FeatureModuleItem> _buildMockFeatures() {
    Map<SubscriptionPlan, bool> planMap(FeatureModule m) {
      final map = <SubscriptionPlan, bool>{};
      for (final plan in SubscriptionPlan.values) {
        map[plan] = plan.includedModules.contains(m.name) ||
            plan.includedModules
                .contains(m.name.replaceAllMapped(
                    RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}'));
      }
      return map;
    }

    return [
      FeatureModuleItem(
        module: FeatureModule.dashboard,
        description:
            'Main dashboard overview with today\'s appointments, patient count, quick stats, and recent activity feed.',
        iconCategory: IconCategory.core,
        isGloballyEnabled: true,
        enabledDoctorsCount: 48,
        totalDoctors: _totalDoctors,
        planAvailability: planMap(FeatureModule.dashboard),
      ),
      FeatureModuleItem(
        module: FeatureModule.revenue,
        description:
            'Track revenue entries, pending payments, invoice generation, receipt downloads, and financial analytics.',
        iconCategory: IconCategory.financial,
        isGloballyEnabled: true,
        enabledDoctorsCount: 48,
        totalDoctors: _totalDoctors,
        planAvailability: planMap(FeatureModule.revenue),
      ),
      FeatureModuleItem(
        module: FeatureModule.patients,
        description:
            'Full patient records management including profiles, visit history, medical notes, and document uploads.',
        iconCategory: IconCategory.core,
        isGloballyEnabled: true,
        enabledDoctorsCount: 48,
        totalDoctors: _totalDoctors,
        planAvailability: planMap(FeatureModule.patients),
      ),
      FeatureModuleItem(
        module: FeatureModule.appointments,
        description:
            'Appointment scheduling, calendar view, slot management, patient reminders, and walk-in tracking.',
        iconCategory: IconCategory.core,
        isGloballyEnabled: true,
        enabledDoctorsCount: 48,
        totalDoctors: _totalDoctors,
        planAvailability: planMap(FeatureModule.appointments),
      ),
      FeatureModuleItem(
        module: FeatureModule.homeVisits,
        description:
            'Schedule and track patient visitations, doctor home visits, session logs, and location details.',
        iconCategory: IconCategory.clinical,
        isGloballyEnabled: true,
        enabledDoctorsCount: 32,
        totalDoctors: _totalDoctors,
        planAvailability: planMap(FeatureModule.homeVisits),
      ),
      FeatureModuleItem(
        module: FeatureModule.aiAssistant,
        description:
            'AI-powered clinical notes summarization, diagnosis suggestions, and LLM chat interface across patient records.',
        iconCategory: IconCategory.advanced,
        isGloballyEnabled: true,
        isBeta: true,
        enabledDoctorsCount: 24,
        totalDoctors: _totalDoctors,
        planAvailability: planMap(FeatureModule.aiAssistant),
      ),
      FeatureModuleItem(
        module: FeatureModule.aiAgenticCalling,
        description:
            'Autonomous AI calling agent for automated patient appointment confirmation, follow-up calls, and feedback surveys.',
        iconCategory: IconCategory.advanced,
        isGloballyEnabled: true,
        isBeta: true,
        enabledDoctorsCount: 12,
        totalDoctors: _totalDoctors,
        planAvailability: planMap(FeatureModule.aiAgenticCalling),
      ),
      FeatureModuleItem(
        module: FeatureModule.omnichannelMessaging,
        description:
            'Unified multi-channel messaging platform for sending instant WhatsApp, Email, and SMS reminders & prescriptions.',
        iconCategory: IconCategory.advanced,
        isGloballyEnabled: true,
        enabledDoctorsCount: 36,
        totalDoctors: _totalDoctors,
        planAvailability: planMap(FeatureModule.omnichannelMessaging),
      ),
      FeatureModuleItem(
        module: FeatureModule.multiDeviceAccess,
        description:
            'Secure multi-device account synchronization across Web and Mobile with real-time session management.',
        iconCategory: IconCategory.core,
        isGloballyEnabled: true,
        enabledDoctorsCount: 48,
        totalDoctors: _totalDoctors,
        planAvailability: planMap(FeatureModule.multiDeviceAccess),
      ),
    ];
  }

  Future<void> loadFeatures() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      state = state.copyWith(
        features: _buildMockFeatures(),
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load features: $e',
      );
    }
  }

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void setCategoryFilter(IconCategory? cat) {
    state = state.copyWith(
      categoryFilter: cat,
      clearCategory: cat == null,
    );
  }

  void setBetaFilter(bool? beta) {
    state = state.copyWith(
      betaFilter: beta,
      clearBeta: beta == null,
    );
  }

  void clearFilters() {
    state = state.copyWith(
      searchQuery: '',
      clearCategory: true,
      clearBeta: true,
    );
  }

  void toggleGlobalEnabled(FeatureModule module) {
    final updated = state.features.map((f) {
      if (f.module == module) {
        return f.copyWith(isGloballyEnabled: !f.isGloballyEnabled);
      }
      return f;
    }).toList();
    state = state.copyWith(features: updated);
  }

  void toggleBeta(FeatureModule module) {
    final updated = state.features.map((f) {
      if (f.module == module) {
        return f.copyWith(isBeta: !f.isBeta);
      }
      return f;
    }).toList();
    state = state.copyWith(features: updated);
  }

  void updateModulePrice(FeatureModule module, double newPrice) {
    final updated = state.features.map((f) {
      if (f.module == module) {
        return f.copyWith(customMonthlyPrice: newPrice);
      }
      return f;
    }).toList();
    state = state.copyWith(features: updated);
  }
}

/// Provider for Feature Management state.
final featureManagementProvider =
    NotifierProvider<FeatureManagementNotifier, FeatureManagementState>(() {
  return FeatureManagementNotifier();
});
