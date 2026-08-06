import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/enums.dart';
import '../models/super_admin_model.dart';
import '../services/auth_service.dart';

/// Auth state for Super Admin.
class SuperAdminAuthState {
  final SuperAdminModel? currentAdmin;
  final bool isLoading;
  final bool isAuthenticated;
  final bool isTwoFARequired;
  final bool isTwoFAVerified;
  final String? errorMessage;
  final String? pendingEmail;

  const SuperAdminAuthState({
    this.currentAdmin,
    this.isLoading = false,
    this.isAuthenticated = false,
    this.isTwoFARequired = false,
    this.isTwoFAVerified = false,
    this.errorMessage,
    this.pendingEmail,
  });

  SuperAdminAuthState copyWith({
    SuperAdminModel? currentAdmin,
    bool? isLoading,
    bool? isAuthenticated,
    bool? isTwoFARequired,
    bool? isTwoFAVerified,
    String? errorMessage,
    String? pendingEmail,
    bool clearError = false,
  }) {
    return SuperAdminAuthState(
      currentAdmin: currentAdmin ?? this.currentAdmin,
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      isTwoFARequired: isTwoFARequired ?? this.isTwoFARequired,
      isTwoFAVerified: isTwoFAVerified ?? this.isTwoFAVerified,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingEmail: pendingEmail ?? this.pendingEmail,
    );
  }
}

/// Provider for Super Admin authentication state.
class SuperAdminAuthNotifier extends Notifier<SuperAdminAuthState> {
  late final SuperAdminAuthService _authService;

  @override
  SuperAdminAuthState build() {
    _authService = SuperAdminAuthService();
    _initialize();
    return const SuperAdminAuthState();
  }

  /// Initialize auth state — check if already logged in as Super Admin.
  Future<void> _initialize() async {
    try {
      final admin = await _authService.getCurrentAdmin();
      if (admin != null && admin.role == UserRole.superAdmin) {
        state = state.copyWith(
          currentAdmin: admin,
          isAuthenticated: true,
          isTwoFARequired: admin.isTwoFAEnabled && !admin.isTwoFAVerified,
          isTwoFAVerified: admin.isTwoFAVerified,
        );
      }
      // If admin is null, the user is either not logged in or not a Super Admin.
      // State remains unauthenticated (default), so the guard will block access.
    } catch (_) {
      // Not authenticated — state remains default (unauthenticated).
    }
  }

  /// Sign in with email and password.
  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true, pendingEmail: email);

    try {
      final admin = await _authService.signIn(email: email, password: password);

      final requires2FA = admin.isTwoFAEnabled && !admin.isTwoFAVerified;

      state = state.copyWith(
        currentAdmin: admin,
        isAuthenticated: !requires2FA,
        isLoading: false,
        isTwoFARequired: requires2FA,
        isTwoFAVerified: admin.isTwoFAVerified,
        errorMessage: null,
      );

      return !requires2FA;
    } catch (e) {
      // Track failed login
      await _authService.trackFailedLogin(email);

      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
      return false;
    }
  }

  /// Verify 2FA code.
  Future<bool> verify2FA(String code) async {
    state = state.copyWith(isLoading: true);

    try {
      final verified = await _authService.verify2FA(code);
      if (verified) {
        state = state.copyWith(
          isTwoFAVerified: true,
          isAuthenticated: true,
          isTwoFARequired: false,
          isLoading: false,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Invalid verification code',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: '2FA verification failed',
      );
      return false;
    }
  }

  /// Sign out.
  Future<void> logout() async {
    await _authService.signOut();
    state = const SuperAdminAuthState();
  }

  /// Clear error message.
  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final superAdminAuthProvider =
    NotifierProvider<SuperAdminAuthNotifier, SuperAdminAuthState>(
  SuperAdminAuthNotifier.new,
);