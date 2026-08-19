import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/api_key_model.dart';
import '../services/api_key_service.dart';

/// State representation for API Key and Usage Management.
class ApiKeyState {
  final List<ApiKeyModel> apiKeys;
  final List<ApiLogModel> apiLogs;
  final bool isLoading;
  final String? errorMessage;
  final String? lastGeneratedKey; // Stores the plain secret key to display once
  final String searchQuery;
  final Map<String, String> systemKeys;

  const ApiKeyState({
    this.apiKeys = const [],
    this.apiLogs = const [],
    this.isLoading = false,
    this.errorMessage,
    this.lastGeneratedKey,
    this.searchQuery = '',
    this.systemKeys = const {},
  });

  ApiKeyState copyWith({
    List<ApiKeyModel>? apiKeys,
    List<ApiLogModel>? apiLogs,
    bool? isLoading,
    String? errorMessage,
    String? lastGeneratedKey,
    String? searchQuery,
    Map<String, String>? systemKeys,
    bool clearGeneratedKey = false,
    bool clearError = false,
  }) {
    return ApiKeyState(
      apiKeys: apiKeys ?? this.apiKeys,
      apiLogs: apiLogs ?? this.apiLogs,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastGeneratedKey: clearGeneratedKey ? null : (lastGeneratedKey ?? this.lastGeneratedKey),
      searchQuery: searchQuery ?? this.searchQuery,
      systemKeys: systemKeys ?? this.systemKeys,
    );
  }

  // ------------- Helper Metrics -------------

  int get activeKeysCount => apiKeys.where((k) => k.isActive).length;

  int get totalRequestCount => apiLogs.length;

  double get successRate {
    if (apiLogs.isEmpty) return 100.0;
    final successCount = apiLogs.where((l) => l.statusCode >= 200 && l.statusCode < 300).length;
    return (successCount / apiLogs.length) * 100.0;
  }

  double get averageLatency {
    if (apiLogs.isEmpty) return 0.0;
    final totalLatency = apiLogs.fold<int>(0, (sum, log) => sum + log.latencyMs);
    return totalLatency / apiLogs.length;
  }

  /// Returns request counts grouped by day for the last 7 days.
  Map<DateTime, int> get dailyRequestCounts {
    final Map<DateTime, int> data = {};
    final now = DateTime.now();
    for (var i = 6; i >= 0; i--) {
      final date = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      data[date] = 0;
    }

    for (final log in apiLogs) {
      final logDate = DateTime(log.timestamp.year, log.timestamp.month, log.timestamp.day);
      if (data.containsKey(logDate)) {
        data[logDate] = (data[logDate] ?? 0) + 1;
      }
    }
    return data;
  }

  /// Returns request counts grouped by endpoint.
  Map<String, int> get endpointUsageCounts {
    final Map<String, int> data = {};
    for (final log in apiLogs) {
      data[log.endpoint] = (data[log.endpoint] ?? 0) + 1;
    }
    return data;
  }
}

/// Notifier to manage the API Keys state.
class ApiKeyNotifier extends Notifier<ApiKeyState> {
  late final SuperAdminApiKeyService _service;

  @override
  ApiKeyState build() {
    _service = SuperAdminApiKeyService();
    return const ApiKeyState();
  }

  /// Fetch all keys and recent usage logs. Auto-seeds mock logs if none exist.
  Future<void> loadKeysAndLogs({bool refresh = false}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final keys = await _service.getApiKeys();
      var logs = await _service.getApiLogs();
      final systemKeys = await _service.getSystemIntegrationKeys();

      // If keys exist but no logs, seed mock data so dashboard chart is filled nicely
      if (keys.isNotEmpty && logs.isEmpty) {
        await _service.seedMockApiLogs(keys);
        logs = await _service.getApiLogs();
      }

      state = state.copyWith(
        apiKeys: keys,
        apiLogs: logs,
        systemKeys: systemKeys,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Generate a new API key. Sets the [lastGeneratedKey] state variable.
  Future<void> createApiKey({
    required String name,
    DateTime? expiresAt,
    int rateLimit = 60,
    required List<String> scopes,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true, clearGeneratedKey: true);
    try {
      final result = await _service.createApiKey(
        name: name,
        expiresAt: expiresAt,
        rateLimit: rateLimit,
        scopes: scopes,
      );

      final newModel = result['model'] as ApiKeyModel;
      final secretKey = result['secretKey'] as String;

      state = state.copyWith(
        apiKeys: [newModel, ...state.apiKeys],
        lastGeneratedKey: secretKey,
        isLoading: false,
      );
      
      // Reload logs (it may recalculate stats)
      loadKeysAndLogs();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Update key properties (name, limit, active state, scopes).
  Future<void> updateApiKey({
    required String id,
    required String name,
    required int rateLimit,
    required bool isActive,
    required List<String> scopes,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _service.updateApiKey(
        id: id,
        name: name,
        rateLimit: rateLimit,
        isActive: isActive,
        scopes: scopes,
      );
      
      // Update state in-place to avoid full reload flickers
      final updatedKeys = state.apiKeys.map((key) {
        if (key.id == id) {
          return key.copyWith(
            name: name,
            rateLimit: rateLimit,
            isActive: isActive,
            scopes: scopes,
          );
        }
        return key;
      }).toList();

      state = state.copyWith(
        apiKeys: updatedKeys,
        isLoading: false,
      );
      
      loadKeysAndLogs(); // Reload logs in case status change alters logs
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Revoke an API Key.
  Future<void> revokeApiKey(String id) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _service.revokeApiKey(id);

      final updatedKeys = state.apiKeys.map((key) {
        if (key.id == id) {
          return key.copyWith(isActive: false);
        }
        return key;
      }).toList();

      state = state.copyWith(
        apiKeys: updatedKeys,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Sets search filter query.
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Clear the generated key from memory once copy modal is closed.
  void clearGeneratedKey() {
    state = state.copyWith(clearGeneratedKey: true);
  }

  /// Save third-party integration config keys.
  Future<void> saveSystemKeys(Map<String, String> keys) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _service.saveSystemIntegrationKeys(keys);
      state = state.copyWith(
        systemKeys: keys,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }
}

/// Provider for API Keys and Usage management.
final apiKeysProvider = NotifierProvider<ApiKeyNotifier, ApiKeyState>(
  ApiKeyNotifier.new,
);
