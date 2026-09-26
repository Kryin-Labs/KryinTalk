import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../api/api_client.dart';
import '../supabase/supabase_service.dart';

const currentPolicyVersion = '2026-09-26';
bool validAccountEmail(String email) =>
    email.trim().length <= 254 &&
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());
String normalizeUsername(String username) =>
    username.trim().replaceFirst(RegExp(r'^@'), '').toLowerCase();

class AuthService {
  AuthService(this._client);
  final ApiClient _client;

  static String errorMessage(Object error) {
    if (error is AuthException) {
      if (error.code == 'invalid_credentials')
        return 'Incorrect email or password.';
      if (error.code == 'email_not_confirmed')
        return 'Please confirm your email before signing in.';
      if (error.code == 'over_email_send_rate_limit' ||
          error.code == 'over_request_rate_limit') {
        return 'Too many requests. Please wait before trying again.';
      }
      if (error.message.toLowerCase().contains('database error')) {
        return 'Account authentication database is temporarily unavailable. Please try again.';
      }
      if (error is AuthRetryableFetchException)
        return "Couldn't reach authentication. Check your connection and try again.";
      return 'Authentication could not be completed. Please try again.';
    }
    if (error is PostgrestException) {
      if (error.code == '42501')
        return 'Your access may have changed. Refresh your status or contact an admin.';
      if (error.code == '22023')
        return 'The account or invite state changed, or the input is invalid. Refresh and try again.';
      if (error.code == 'P0002')
        return 'This account is no longer available. Refresh the list.';
      return 'Account setup could not be loaded. Please retry or contact an admin.';
    }
    return 'Could not connect. Please check your connection and try again.';
  }

  Future<LoginResult> login(String email, String password,
      {bool agreed = false}) async {
    if (!agreed)
      return const LoginResult(
          success: false,
          error:
              'Please agree to the Terms and acknowledge the Privacy Policy.');
    if (!validAccountEmail(email) || password.isEmpty)
      return const LoginResult(
          success: false, error: 'Enter your email address and password.');
    if (!SupabaseService.instance.isInitialized) {
      return const LoginResult(
          success: false,
          error:
              'KryinTalk could not initialize Supabase. Please reload the app.');
    }
    try {
      await SupabaseService.instance.signIn(email: email, password: password);
      final session = SupabaseService.instance.client.auth.currentSession;
      if (session == null)
        return const LoginResult(
            success: false,
            error: 'Sign in could not be completed. Please retry.');
      await _client.setToken(session.accessToken);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sp_user_id', session.user.id);
      await prefs.setString('sp_user_email', email.trim());
      try {
        await SupabaseService.instance.client.rpc('record_account_consent',
            params: {'p_version': currentPolicyVersion});
      } catch (_) {
        return LoginResult(
            success: true,
            userId: session.user.id,
            error: 'Please retry saving your agreement to continue.');
      }
      return LoginResult(success: true, userId: session.user.id);
    } catch (error) {
      return LoginResult(success: false, error: errorMessage(error));
    }
  }

  Future<RegistrationResult> register(
      {required String email,
      required String username,
      required String displayName,
      required String password,
      bool agreed = false}) async {
    if (!agreed)
      return const RegistrationResult(
          error:
              'Please agree to the Terms and acknowledge the Privacy Policy.');
    if (!validAccountEmail(email) ||
        !RegExp(r'^[a-z0-9_]{3,100}$').hasMatch(normalizeUsername(username)) ||
        displayName.trim().isEmpty ||
        displayName.trim().length > 100 ||
        password.length < 8) {
      return const RegistrationResult(
          error: 'Please complete the required account fields.');
    }
    if (!SupabaseService.instance.isInitialized)
      return const RegistrationResult(
          error: 'Cloud registration is unavailable. Please reload and retry.');
    try {
      final available = await SupabaseService.instance.client.rpc(
          'is_signup_username_available',
          params: {'p_username': normalizeUsername(username)});
      if (available != true)
        return const RegistrationResult(
            error: 'That username is unavailable. Choose another.');
      await SupabaseService.instance.signUp(
          email: email,
          username: normalizeUsername(username),
          displayName: displayName,
          password: password);
      return const RegistrationResult(
          success: true, confirmationRequired: true);
    } catch (error) {
      return RegistrationResult(error: errorMessage(error));
    }
  }

  Future<void> logout() async {
    SupabaseService.instance.invalidateConversationsCache();
    SupabaseService.instance.invalidateUsersCache();
    if (SupabaseService.instance.hasSession) {
      try {
        await SupabaseService.instance.client
            .from('users')
            .update({'presence_status': 'offline'})
            .eq('id', SupabaseService.instance.client.auth.currentUser!.id)
            .timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
    await _client.clearToken();
    try {
      if (SupabaseService.instance.hasSession)
        await SupabaseService.instance.client.auth
            .signOut(scope: SignOutScope.local);
    } finally {
      final prefs = await SharedPreferences.getInstance();
      for (final key in [
        'sp_user_id',
        'sp_user_email',
        'sp_user_name',
        'sp_user_role',
        'sp_is_superadmin',
        'user_id'
      ]) {
        await prefs.remove(key);
      }
    }
  }

  Future<Map<String, dynamic>?> getProfile() =>
      SupabaseService.instance.getCurrentUserProfile();
  Future<bool> isAuthenticated() async => SupabaseService.instance.hasSession;
}

class LoginResult {
  const LoginResult(
      {required this.success, this.token, this.userId, this.error});
  final bool success;
  final String? token, userId, error;
}

class RegistrationResult {
  const RegistrationResult(
      {this.success = false, this.confirmationRequired = false, this.error});
  final bool success, confirmationRequired;
  final String? error;
}
