/// ConnectHub — In-App OTA Update Checker & Direct Installer.
///
/// Checks /app/version on the backend and allows users to update directly
/// from within the app without Play Store or manual file transfers.
library;

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../debug/debug_inspector.dart';

class AppUpdater {
  static final AppUpdater instance = AppUpdater._();
  AppUpdater._();

  static const String currentVersion = '0.1.0';
  static const int currentBuildNumber = 1;

  final ValueNotifier<Map<String, dynamic>?> updateAvailableNotifier = ValueNotifier(null);

  Future<void> checkForUpdates(BuildContext context, {bool showNoUpdateDialog = false}) async {
    try {
      final baseUrl = AppConfig.instance.currentBaseUrl;
      final dio = Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 3)));
      final res = await dio.get('/app/version');

      if (res.statusCode == 200 && res.data is Map) {
        final data = Map<String, dynamic>.from(res.data);
        final latestBuild = (data['build_number'] as num?)?.toInt() ?? 1;

        if (latestBuild > currentBuildNumber) {
          updateAvailableNotifier.value = data;
          if (showNoUpdateDialog && context.mounted) {
            showUpdateDialog(context, data);
          }
        } else {
          updateAvailableNotifier.value = null;
          if (showNoUpdateDialog && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF0F766E),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                content: Text('You are on the latest version ($currentVersion)!'),
              ),
            );
          }
        }
      }
    } catch (_) {
      if (showNoUpdateDialog && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            content: const Text('Could not reach update server.'),
          ),
        );
      }
    }
  }

  void showUpdateDialog(BuildContext context, Map<String, dynamic> updateData) {
    final version = updateData['version'] ?? 'Latest';
    final notes = updateData['release_notes'] ?? 'Performance improvements and bug fixes.';
    final downloadUrl = updateData['download_url'] ?? '/connecthub-debug.apk';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFAF9F6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFCCFBF1)),
              ),
              child: const Icon(Icons.system_update_rounded, color: Color(0xFF0F766E), size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Update Available (v$version)',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1C1917),
                    ),
                  ),
                  const Text(
                    'Direct Over-The-Air Update',
                    style: TextStyle(fontSize: 11, color: Color(0xFF78716C)),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE6E4E0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "What's New:",
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notes,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1C1917),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tap "Install Update" to download and apply the new build directly.',
              style: TextStyle(fontSize: 11, color: Color(0xFF78716C)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later', style: TextStyle(color: Color(0xFF78716C), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Install Update', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () async {
              Navigator.pop(ctx);
              final fullUrl = downloadUrl.startsWith('http')
                  ? downloadUrl
                  : '${AppConfig.instance.currentBaseUrl}$downloadUrl';
              final uri = Uri.parse(fullUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
    );
  }
}
