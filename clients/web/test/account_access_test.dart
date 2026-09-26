import 'package:flutter_test/flutter_test.dart';
import 'package:connecthub_web/core/auth/auth_provider.dart';
import 'package:connecthub_web/core/router/app_router.dart';

void main() {
  const pending = AuthState(isAuthenticated: true, isLoading: false, user: {
    'id': 'pending',
    'email_confirmed': true,
    'is_active': true,
    'is_suspended': false,
    'access_status': 'pending',
    'policy_version': '2026-09-26',
  });
  test('pending and cached admin metadata cannot enter protected app', () {
    expect(pending.hasAppAccess, isFalse);
    const forged = AuthState(
        isAuthenticated: true,
        isLoading: false,
        user: {'role': 'admin', 'is_super_admin': true});
    expect(forged.isAdmin, isFalse);
    for (final route in [
      '/dashboard',
      '/files',
      '/join/group',
      '/admin/users'
    ]) {
      expect(accountRedirect(pending, Uri.parse(route)), '/access');
    }
  });
  test('approved access requires every authoritative flag and current consent',
      () {
    final user = {
      ...pending.user!,
      'access_status': 'approved',
      'role': 'member',
      'app_access': true
    };
    final approved =
        AuthState(isAuthenticated: true, isLoading: false, user: user);
    expect(approved.hasAppAccess, isTrue);
    expect(accountRedirect(approved, Uri.parse('/access')), '/dashboard');
    for (final field in [
      'app_access',
      'email_confirmed',
      'is_active',
      'is_suspended',
      'access_status',
      'policy_version'
    ]) {
      final incomplete = {...user}..remove(field);
      expect(AuthState(isAuthenticated: true, user: incomplete).hasAppAccess,
          isFalse);
    }
    final stale = AuthState(
        isAuthenticated: true,
        isLoading: false,
        user: {...user, 'policy_version': 'old'});
    expect(accountRedirect(stale, Uri.parse('/dashboard')), '/consent');
  });
  test('loading and missing profile cannot mount protected shell', () {
    expect(accountRedirect(const AuthState(), Uri.parse('/dashboard')),
        '/loading');
    expect(
        accountRedirect(
            const AuthState(isAuthenticated: true, isLoading: false),
            Uri.parse('/dashboard')),
        '/access');
    expect(accountRedirect(const AuthState(), Uri.parse('/auth/callback')),
        isNull);
    expect(
        accountRedirect(const AuthState(isLoading: false), Uri.parse('/files')),
        '/login');
  });
}
