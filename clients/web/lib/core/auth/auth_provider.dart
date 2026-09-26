import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../api/api_client.dart';
import '../supabase/supabase_service.dart';
import '../notifications/web_notification_service.dart';
import 'auth_service.dart';

class AuthState {
  const AuthState(
      {this.isAuthenticated = false,
      this.isLoading = true,
      this.user,
      this.error});
  final bool isAuthenticated, isLoading;
  final Map<String, dynamic>? user;
  final String? error;
  AuthState copyWith(
          {bool? isAuthenticated,
          bool? isLoading,
          Map<String, dynamic>? user,
          String? error}) =>
      AuthState(
          isAuthenticated: isAuthenticated ?? this.isAuthenticated,
          isLoading: isLoading ?? this.isLoading,
          user: user ?? this.user,
          error: error);
  String? get userId => user?['id']?.toString();
  String get displayName => user?['display_name']?.toString() ?? 'User';
  String get email => user?['email']?.toString() ?? '';
  bool get hasAppAccess =>
      isAuthenticated &&
      !isLoading &&
      user?['email_confirmed'] == true &&
      user?['is_active'] == true &&
      user?['is_suspended'] == false &&
      user?['access_status'] == 'approved' &&
      user?['policy_version'] == currentPolicyVersion &&
      user?['app_access'] == true;
  bool get needsPolicyAcceptance =>
      isAuthenticated &&
      user != null &&
      user?['policy_version'] != currentPolicyVersion;
  bool get isSuperAdmin => hasAppAccess && user?['is_super_admin'] == true;
  String get role => hasAppAccess ? (user?['role']?.toString() ?? '') : '';
  bool get isAdmin => hasAppAccess && (isSuperAdmin || role == 'admin');
  bool get isManager => hasAppAccess && (isAdmin || role == 'manager');
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final api = ref.watch(apiClientProvider);
  return AuthNotifier(AuthService(api), api);
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._authService, ApiClient api, {bool initialize = true})
      : super(const AuthState()) {
    api.onAuthFailure = () {
      if (mounted) refreshProfile();
    };
    api.onAccessDenied = () {
      if (mounted && !state.isLoading) refreshProfile();
    };
    SupabaseService.instance.onAccessDenied = api.onAccessDenied;
    if (!initialize) return;
    if (SupabaseService.instance.isInitialized) {
      _subscription = SupabaseService.instance.client.auth.onAuthStateChange
          .listen((change) {
        if (!mounted || _explicitAction) return;
        if (change.event == sb.AuthChangeEvent.signedOut) {
          ++_epoch;
          _clearProtected();
          state = const AuthState(isLoading: false);
        } else if (change.session != null) {
          refreshProfile();
        }
      });
    }
    refreshProfile();
  }
  final AuthService _authService;
  StreamSubscription<sb.AuthState>? _subscription;
  DateTime? lastAccessCheck;
  int _epoch = 0;
  bool _explicitAction = false;
  void _clearProtected() {
    SupabaseService.instance.invalidateUsersCache();
    SupabaseService.instance.invalidateConversationsCache();
    WebNotificationService.instance.setAccountAccess(false);
  }

  Future<void> refreshProfile() async {
    final epoch = ++_epoch;
    final signedIn = await _authService.isAuthenticated();
    if (!mounted || epoch != _epoch) return;
    if (!signedIn) {
      _clearProtected();
      state = const AuthState(isLoading: false);
      return;
    }
    _clearProtected();
    state = const AuthState(isAuthenticated: true, isLoading: true);
    try {
      final profile = await _authService.getProfile();
      if (!mounted || epoch != _epoch) return;
      state = AuthState(
          isAuthenticated: true,
          isLoading: false,
          user: profile,
          error: profile == null
              ? 'Your account setup is unavailable. Retry or contact an admin.'
              : null);
      WebNotificationService.instance.setAccountAccess(state.hasAppAccess);
    } catch (error) {
      if (mounted && epoch == _epoch)
        state = AuthState(
            isAuthenticated: true,
            isLoading: false,
            error: AuthService.errorMessage(error));
    }
  }

  Future<bool> login(String email, String password,
      {bool agreed = false}) async {
    if (_explicitAction || !agreed) return false;
    _explicitAction = true;
    final epoch = ++_epoch;
    _clearProtected();
    state = const AuthState(isLoading: true);
    try {
      final result = await _authService.login(email, password, agreed: agreed);
      if (!mounted || epoch != _epoch) {
        if (SupabaseService.instance.hasSession &&
            SupabaseService.instance.client.auth.currentUser?.id ==
                result.userId) await _authService.logout();
        return false;
      }
      if (!result.success) {
        state = AuthState(isLoading: false, error: result.error);
        return false;
      }
      await refreshProfile();
      if (mounted && result.error != null)
        state = state.copyWith(error: result.error);
      return true;
    } finally {
      _explicitAction = false;
    }
  }

  Future<RegistrationResult> register(
      {required String email,
      required String username,
      required String displayName,
      required String password,
      bool agreed = false}) async {
    if (_explicitAction || !agreed)
      return const RegistrationResult(error: 'Agreement is required.');
    _explicitAction = true;
    final epoch = ++_epoch;
    _clearProtected();
    state = const AuthState(isLoading: true);
    try {
      final result = await _authService.register(
          email: email,
          username: username,
          displayName: displayName,
          password: password,
          agreed: agreed);
      if (mounted && epoch == _epoch)
        state = AuthState(isLoading: false, error: result.error);
      return result;
    } finally {
      _explicitAction = false;
    }
  }

  Future<void> acceptPolicies() async {
    await SupabaseService.instance.client.rpc('record_account_consent',
        params: {'p_version': currentPolicyVersion});
    await refreshProfile();
  }

  Future<void> logout() async {
    lastAccessCheck = null;
    ++_epoch;
    _clearProtected();
    state = const AuthState(isLoading: true);
    try {
      await _authService.logout();
    } catch (_) {}
    if (mounted) state = const AuthState(isLoading: false);
  }

  @override
  void dispose() {
    ++_epoch;
    _subscription?.cancel();
    super.dispose();
  }
}
