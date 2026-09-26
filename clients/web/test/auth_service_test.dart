import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connecthub_web/core/api/api_client.dart';
import 'package:connecthub_web/core/auth/auth_service.dart';
import 'package:dio/dio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('unknown cloud requests never leave the Supabase bridge', () async {
    final client = ApiClient();
    await expectLater(
        client.dio.get('/retired-endpoint'),
        throwsA(isA<DioException>()
            .having((e) => e.response?.statusCode, 'status', 401)));
    client.dio.close();
  });

  test('auth errors distinguish invalid credentials from schema failures', () {
    expect(
        AuthService.errorMessage(const AuthException(
            'Invalid login credentials',
            code: 'invalid_credentials')),
        'Incorrect email or password.');
    expect(
        AuthService.errorMessage(AuthRetryableFetchException(
            message: 'Database error querying schema', statusCode: '500')),
        contains('database'));
    expect(
        AuthService.errorMessage(const AuthException('Email not confirmed',
            code: 'email_not_confirmed')),
        contains('confirm'));
  });

  test('cached cloud identity alone does not authenticate a user', () async {
    SharedPreferences.setMockInitialValues({
      'sp_user_id': 'stale-user',
      'sp_is_superadmin': true,
      'auth_token': 'supabase_session_stale-user',
    });
    final client = ApiClient();
    expect(await AuthService(client).isAuthenticated(), isFalse);
    client.dio.close();
  });

  test('the retired local API cannot authenticate a production user', () async {
    final client = ApiClient();
    final service = AuthService(client);
    final result = await service
        .login('user@connecthub.local', 'valid-test-password', agreed: true);
    expect(result.success, isFalse);
    expect(result.error, contains('initialize Supabase'));
    expect(await client.getToken(), isNull);
    client.dio.close();
  });
}
