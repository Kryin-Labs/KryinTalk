/// KryinTalk — App Entry Point.
///
/// Initializes Riverpod, sets up theming and routing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:ui';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/debug/debug_inspector.dart';
import 'core/supabase/supabase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase Client
  await SupabaseService.initialize();

  // Initialize AppConfig for dynamic backend endpoints
  await AppConfig.instance.initialize();

  // Global Flutter error handler
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    DebugLogger.instance.logError(
      'UI Exception: ${details.exceptionAsString()}',
      details: details.summary.toString(),
      stackTrace: details.stack?.toString(),
    );
  };

  // Global Platform/Async error handler
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    DebugLogger.instance.logError(
      'Platform/Async Error: $error',
      stackTrace: stack.toString(),
    );
    return true;
  };

  runApp(const ProviderScope(child: KryinTalkApp()));
}

class KryinTalkApp extends ConsumerWidget {
  const KryinTalkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'KryinTalk',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
