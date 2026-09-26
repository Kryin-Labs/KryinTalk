import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connecthub_web/core/api/api_client.dart';
import 'package:connecthub_web/core/auth/auth_provider.dart';
import 'package:connecthub_web/core/auth/auth_service.dart';
import 'package:connecthub_web/core/theme/app_theme.dart';
import 'package:connecthub_web/features/auth/login_screen.dart';
import 'package:connecthub_web/features/auth/register_screen.dart';
import 'package:connecthub_web/features/admin/user_management_screen.dart';

class FakeAuth extends AuthNotifier {
  FakeAuth() : super(AuthService(ApiClient()), ApiClient(), initialize: false) {
    state = const AuthState(isLoading: false);
  }
  int logins = 0, signups = 0;
  Completer<void>? gate;
  @override
  Future<bool> login(String email, String password,
      {bool agreed = false}) async {
    logins++;
    if (gate != null) await gate!.future;
    return false;
  }

  @override
  Future<RegistrationResult> register(
      {required String email,
      required String username,
      required String displayName,
      required String password,
      bool agreed = false}) async {
    signups++;
    if (gate != null) await gate!.future;
    return const RegistrationResult(error: 'Test account error');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> show(WidgetTester tester, Widget screen, FakeAuth auth,
      {bool dark = false, double scale = 1}) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [authProvider.overrideWith((ref) => auth)],
        child: MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(ctx)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: screen)));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, String key, String value) async {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pump();
  }

  Future<void> agree(WidgetTester tester) async {
    final checkbox = find.byKey(const ValueKey('policy-agreement'));
    await tester.ensureVisible(checkbox);
    await tester.tap(checkbox);
    await tester.pump();
  }

  for (final register in [false, true]) {
    testWidgets(
        register
            ? 'signup guards agreement, mismatch, Enter and duplicate submits'
            : 'every fresh login requires agreement and guards Enter',
        (tester) async {
      final fake = FakeAuth();
      final submit = ValueKey(register ? 'register-submit' : 'login-submit');
      await show(tester,
          register ? const RegisterScreen() : const LoginScreen(), fake);
      expect(tester.widget<FilledButton>(find.byKey(submit)).onPressed, isNull);
      if (register) {
        await fill(tester, 'register-name', 'Test Person');
        await fill(tester, 'register-username', 'Test_Person');
        await fill(tester, 'register-email', 'person@example.test');
        await fill(tester, 'register-password', 'a strong test password');
        await fill(tester, 'register-confirm', 'different password');
        await agree(tester);
        expect(
            tester.widget<FilledButton>(find.byKey(submit)).onPressed, isNull);
        await agree(tester);
        await fill(tester, 'register-confirm', 'a strong test password');
      } else {
        await fill(tester, 'login-email', 'person@example.test');
        await fill(tester, 'login-password', 'a strong test password');
      }
      expect(tester.widget<FilledButton>(find.byKey(submit)).onPressed, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(fake.logins + fake.signups, 0);
      await agree(tester);
      expect(
          tester.widget<FilledButton>(find.byKey(submit)).onPressed, isNotNull);
      await agree(tester);
      expect(tester.widget<FilledButton>(find.byKey(submit)).onPressed, isNull);
      final terms = find.text('Terms of Service');
      await tester.ensureVisible(terms);
      await tester.tap(terms);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Close'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<CheckboxListTile>(
                  find.byKey(const ValueKey('policy-agreement')))
              .value,
          isFalse);
      await agree(tester);
      fake.gate = Completer<void>();
      await tester.ensureVisible(find.byKey(submit));
      await tester.tap(find.byKey(submit));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(submit)).onPressed, isNull);
      expect(fake.logins + fake.signups, 1);
      fake.gate!.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      final fresh = FakeAuth();
      await show(tester,
          register ? const RegisterScreen() : const LoginScreen(), fresh);
      expect(
          tester
              .widget<CheckboxListTile>(
                  find.byKey(const ValueKey('policy-agreement')))
              .value,
          isFalse);
    });
  }
  for (final width in [360.0, 768.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('forms fit width $width dark $dark at large text',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final screen in [const LoginScreen(), const RegisterScreen()]) {
          await show(tester, screen, FakeAuth(), dark: dark, scale: 2);
          await tester.ensureVisible(find.byKey(ValueKey(
              screen is LoginScreen ? 'login-submit' : 'register-submit')));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
  test(
      'admin target limits and suspended account actions match server boundaries',
      () {
    const admin = AuthState(isAuthenticated: true, isLoading: false, user: {
      'id': 'admin',
      'role': 'admin',
      'email_confirmed': true,
      'is_active': true,
      'is_suspended': false,
      'app_access': true,
      'access_status': 'approved',
      'policy_version': currentPolicyVersion
    });
    expect(
        canManageAppAccount(admin, {'id': 'member', 'role': 'member'}), isTrue);
    expect(
        canManageAppAccount(admin, {'id': 'admin', 'role': 'admin'}), isFalse);
    expect(canManageAppAccount(admin, {'id': 'owner', 'role': 'super_admin'}),
        isFalse);
    expect(canManageAppAccount(const AuthState(), {'id': 'pending'}), isFalse);
    expect(
        accountReviewActions(
            {'access_status': 'approved', 'is_suspended': true}),
        ['restore', 'revoke']);
  });
}
