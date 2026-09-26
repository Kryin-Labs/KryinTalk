import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connecthub_web/core/api/api_client.dart';
import 'package:connecthub_web/core/auth/auth_provider.dart';
import 'package:connecthub_web/core/auth/auth_service.dart';
import 'package:connecthub_web/core/supabase/supabase_service.dart';
import 'package:connecthub_web/features/auth/access_screen.dart';
import 'package:connecthub_web/features/auth/confirmation_screen.dart';

const profile = {
  'id': 'pending',
  'email': 'pending@example.test',
  'username': 'pending',
  'email_confirmed': true,
  'is_active': true,
  'is_suspended': false,
  'access_status': 'pending',
  'policy_version': currentPolicyVersion,
  'app_access': false
};

class ControlledService extends AuthService {
  ControlledService() : super(ApiClient());
  final requests = <Completer<Map<String, dynamic>?>>[];
  @override
  Future<bool> isAuthenticated() async => true;
  @override
  Future<Map<String, dynamic>?> getProfile() {
    final c = Completer<Map<String, dynamic>?>();
    requests.add(c);
    return c.future;
  }

  @override
  Future<void> logout() async {}
}

class OnboardingAuth extends AuthNotifier {
  OnboardingAuth(Map<String, dynamic>? user)
      : super(AuthService(ApiClient()), ApiClient(), initialize: false) {
    state = AuthState(isAuthenticated: true, isLoading: false, user: user);
  }
  int checks = 0;
  @override
  Future<void> refreshProfile() async {
    checks++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('logout discards a profile response that arrives late', () async {
    final service = ControlledService();
    final active = AuthNotifier(service, ApiClient(), initialize: false);
    final work = active.refreshProfile();
    await Future<void>.delayed(Duration.zero);
    await active.logout();
    service.requests.single.complete(
        {...profile, 'access_status': 'approved', 'app_access': true});
    await work;
    expect(active.state.isAuthenticated, false);
    expect(active.state.user, isNull);
    active.dispose();
  });
  test('newer refresh wins over an older response', () async {
    final service = ControlledService(),
        auth = AuthNotifier(service, ApiClient(), initialize: false);
    final old = auth.refreshProfile();
    await Future<void>.delayed(Duration.zero);
    final latest = auth.refreshProfile();
    await Future<void>.delayed(Duration.zero);
    service.requests[1].complete(profile);
    await latest;
    service.requests[0].complete(
        {...profile, 'access_status': 'approved', 'app_access': true});
    await old;
    expect(auth.state.hasAppAccess, false);
    expect(auth.state.user?['access_status'], 'pending');
    auth.dispose();
  });
  Future<void> show(
      WidgetTester tester, Widget screen, OnboardingAuth auth) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [authProvider.overrideWith((ref) => auth)],
        child: MaterialApp(home: screen)));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'pending screen offers contact, code and debounced status outside chats',
      (tester) async {
    final auth = OnboardingAuth(profile);
    await show(tester, const AccessScreen(), auth);
    expect(find.byKey(const ValueKey('access-code')), findsOneWidget);
    await tester.ensureVisible(find.text('Check status'));
    await tester.tap(find.text('Check status'));
    await tester.pumpAndSettle();
    expect(auth.checks, 1);
    final check = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Check status'));
    expect(check.onPressed, isNull);
    await tester.ensureVisible(find.text('Contact admin'));
    await tester.tap(find.text('Contact admin'));
    await tester.pumpAndSettle();
    expect(find.text('Request admin access'), findsOneWidget);
    expect(find.text('Copy request details'), findsOneWidget);
    expect(
        find.text(
            'Ask the person who invited you to contact an administrator.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('restricted account has no code entry', (tester) async {
    await show(tester, const AccessScreen(),
        OnboardingAuth({...profile, 'is_suspended': true}));
    expect(find.byKey(const ValueKey('access-code')), findsNothing);
    expect(find.text('Contact admin'), findsOneWidget);
  });
  testWidgets(
      'confirmation resend starts disabled and refresh accepts a manually entered email',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: CheckEmailScreen(email: 'pending@example.test')));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(find.text('Resend in 60s'), findsOneWidget);
    await tester.pumpWidget(
        const MaterialApp(home: CheckEmailScreen(key: ValueKey('refresh'))));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), 'pending@example.test');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'callback distinguishes confirmation success and invalid recovery',
      (tester) async {
    SupabaseService.callbackSucceeded = false;
    await show(tester, const AuthCallbackScreen(), OnboardingAuth(null));
    expect(find.text('Request another email'), findsOneWidget);
    SupabaseService.callbackSucceeded = true;
    await tester.pumpWidget(const SizedBox());
    await show(tester, const AuthCallbackScreen(), OnboardingAuth(null));
    expect(find.text('Email confirmed'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    SupabaseService.callbackSucceeded = false;
  });
}
