/// ConnectHub — In-App Debug Inspector, Error Diagnostics & Dynamic Server Switcher.
///
/// Enables real-time error inspection, network logging, and dynamic backend URL switching
/// between Localhost, Android Emulator (10.0.2.2), USB Tethering, and Local Wi-Fi (192.168.1.14).
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../updater/app_updater.dart';
import '../supabase/supabase_service.dart';

enum LogType { info, warning, error, network }

class LogEntry {
  final DateTime timestamp;
  final LogType type;
  final String title;
  final String? details;
  final String? stackTrace;
  final int? statusCode;

  LogEntry({
    required this.timestamp,
    required this.type,
    required this.title,
    this.details,
    this.stackTrace,
    this.statusCode,
  });
}

class DebugLogger {
  DebugLogger._();
  static final DebugLogger instance = DebugLogger._();

  final List<LogEntry> _logs = [];
  final ValueNotifier<int> logCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> hasErrorsNotifier = ValueNotifier<bool>(false);

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void log(LogType type, String title,
      {String? details, String? stackTrace, int? statusCode}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      type: type,
      title: title,
      details: details,
      stackTrace: stackTrace,
      statusCode: statusCode,
    );

    if (_logs.length >= 150) {
      _logs.removeAt(0);
    }
    _logs.add(entry);
    logCountNotifier.value = _logs.length;

    if (type == LogType.error) {
      hasErrorsNotifier.value = true;
    }
  }

  void logInfo(String title, {String? details}) =>
      log(LogType.info, title, details: details);
  void logWarning(String title, {String? details}) =>
      log(LogType.warning, title, details: details);
  void logError(String title,
          {String? details, String? stackTrace, int? statusCode}) =>
      log(LogType.error, title,
          details: details, stackTrace: stackTrace, statusCode: statusCode);
  void logNetwork(String title, {String? details, int? statusCode}) =>
      log(LogType.network, title, details: details, statusCode: statusCode);

  void clearLogs() {
    _logs.clear();
    logCountNotifier.value = 0;
    hasErrorsNotifier.value = false;
  }
}

class AppConfig {
  AppConfig._();
  static final AppConfig instance = AppConfig._();

  static const String defaultLocalhost = 'http://127.0.0.1:8000';
  static const String defaultEmulator = 'http://10.0.2.2:8000';
  static const String defaultWifiLan = 'http://192.168.1.14:8000';
  static const bool useLocalApi = false;
  static const String productionBaseUrl = SupabaseConfig.projectUrl;

  String _currentBaseUrl = useLocalApi ? defaultLocalhost : productionBaseUrl;
  String get currentBaseUrl => _currentBaseUrl;

  final ValueNotifier<String> baseUrlNotifier =
      ValueNotifier<String>(useLocalApi ? defaultLocalhost : productionBaseUrl);
  final ValueNotifier<bool> serverHealthyNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<int> serverLatencyNotifier = ValueNotifier<int>(0);

  Dio? _dioInstance;

  void attachDio(Dio dio) {
    _dioInstance = dio;
  }

  Future<void> initialize() async {
    if (!useLocalApi) {
      _currentBaseUrl = productionBaseUrl;
      baseUrlNotifier.value = _currentBaseUrl;
      _dioInstance?.options.baseUrl = _currentBaseUrl;
      await pingServer();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString('custom_server_base_url');

      if (savedUrl != null && savedUrl.isNotEmpty) {
        _currentBaseUrl = savedUrl;
      } else {
        // Auto-detect default based on platform
        if (kIsWeb) {
          final host = Uri.base.host;
          final scheme = Uri.base.scheme.isNotEmpty ? Uri.base.scheme : 'http';
          if (host.isNotEmpty && !host.startsWith('null') && host != 'null') {
            _currentBaseUrl = '$scheme://$host:8000';
          } else {
            _currentBaseUrl = defaultLocalhost;
          }
        } else if (defaultTargetPlatform == TargetPlatform.android) {
          _currentBaseUrl = defaultWifiLan; // Default physical Android to Wi-Fi
        } else {
          _currentBaseUrl = defaultLocalhost;
        }
      }
      baseUrlNotifier.value = _currentBaseUrl;
      if (_dioInstance != null) {
        _dioInstance!.options.baseUrl = _currentBaseUrl;
      }
    } catch (_) {}

    // Check connectivity on launch
    pingServer();
  }

  Future<void> setBaseUrl(String newUrl) async {
    if (!useLocalApi) {
      _currentBaseUrl = productionBaseUrl;
      baseUrlNotifier.value = _currentBaseUrl;
      _dioInstance?.options.baseUrl = _currentBaseUrl;
      await pingServer();
      return;
    }
    String cleanUrl = newUrl.trim();
    if (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    _currentBaseUrl = cleanUrl;
    baseUrlNotifier.value = _currentBaseUrl;

    if (_dioInstance != null) {
      _dioInstance!.options.baseUrl = _currentBaseUrl;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('custom_server_base_url', _currentBaseUrl);
    } catch (_) {}

    DebugLogger.instance
        .logInfo('Server base URL updated', details: _currentBaseUrl);
    await pingServer();
  }

  Future<bool> pingServer([String? testUrl]) async {
    final stopwatch = Stopwatch()..start();
    try {
      if (!useLocalApi) {
        stopwatch.stop();
        serverLatencyNotifier.value = stopwatch.elapsedMilliseconds;
        serverHealthyNotifier.value = SupabaseService.instance.isInitialized;
        return serverHealthyNotifier.value;
      }
      if (SupabaseService.instance.hasSession) {
        await SupabaseService.instance.client
            .from('users')
            .select('id')
            .limit(1);
        stopwatch.stop();
        final latency = stopwatch.elapsedMilliseconds;
        serverLatencyNotifier.value = latency;
        serverHealthyNotifier.value = true;
        DebugLogger.instance.logNetwork(
            'Supabase Cloud Health OK ($latency ms)',
            details: 'Supabase Cloud Connected');
        return true;
      }

      final targetUrl = testUrl ?? _currentBaseUrl;
      final pingDio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 4),
        receiveTimeout: const Duration(seconds: 4),
      ));
      final response = await pingDio.get('$targetUrl/health');
      stopwatch.stop();

      final latency = stopwatch.elapsedMilliseconds;
      serverLatencyNotifier.value = latency;

      if (response.statusCode == 200) {
        if (targetUrl == _currentBaseUrl) {
          serverHealthyNotifier.value = true;
        }
        DebugLogger.instance.logNetwork('Server Health Ping OK ($latency ms)',
            details: '$targetUrl/health -> 200 OK');
        return true;
      } else {
        if (targetUrl == _currentBaseUrl) {
          serverHealthyNotifier.value = false;
        }
        return false;
      }
    } catch (e) {
      stopwatch.stop();
      serverHealthyNotifier.value = false;
      DebugLogger.instance.logWarning('Server Ping Failed', details: '$e');
      return false;
    }
  }
}

/// Top Debug Button Widget for Header / Login Screen
class DebugTopButton extends StatelessWidget {
  final bool compact;

  /// Feature flag: Set to true to re-enable server status bar in top navbar & login screen.
  static const bool enabled = false;

  const DebugTopButton({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();

    return ValueListenableBuilder<bool>(
      valueListenable: AppConfig.instance.serverHealthyNotifier,
      builder: (context, isHealthy, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: DebugLogger.instance.hasErrorsNotifier,
          builder: (context, hasErrors, _) {
            final dotColor = hasErrors
                ? const Color(0xFFEF4444)
                : (isHealthy
                    ? const Color(0xFF10B981)
                    : const Color(0xFFF59E0B));

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => showDialog(
                  context: context,
                  builder: (ctx) => const DebugInspectorModal(),
                ),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: EdgeInsets.symmetric(
                      horizontal: compact ? 8 : 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE6E4E0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        compact
                            ? 'Debug'
                            : (hasErrors ? 'Errors' : 'Server OK'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: hasErrors
                              ? const Color(0xFFEF4444)
                              : const Color(0xFF1C1917),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// In-App Diagnostics & Server Configuration Modal
class DebugInspectorModal extends StatefulWidget {
  const DebugInspectorModal({super.key});

  @override
  State<DebugInspectorModal> createState() => _DebugInspectorModalState();
}

class _DebugInspectorModalState extends State<DebugInspectorModal>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _urlController = TextEditingController();
  bool _isTesting = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _urlController.text = AppConfig.instance.currentBaseUrl;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _applyUrl(String url) async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    final success = await AppConfig.instance.pingServer(url);
    if (success) {
      await AppConfig.instance.setBaseUrl(url);
      _urlController.text = url;
      setState(() {
        _isTesting = false;
        _testResult =
            'Connected successfully (${AppConfig.instance.serverLatencyNotifier.value} ms)';
      });
    } else {
      setState(() {
        _isTesting = false;
        _testResult = 'Connection failed. Verify server is running.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFFFAF9F6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 640,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.developer_mode_rounded,
                      color: Color(0xFF0F766E), size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ConnectHub Diagnostics & Server Settings',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1C1917)),
                      ),
                      Text(
                        'Live network inspector, error console & server switcher',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF78716C)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF78716C)),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tabs
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF0F766E),
              unselectedLabelColor: const Color(0xFF78716C),
              indicatorColor: const Color(0xFF0F766E),
              indicatorWeight: 2.5,
              tabs: const [
                Tab(
                    text: 'Server Connection',
                    icon: Icon(Icons.dns_outlined, size: 18)),
                Tab(
                    text: 'Error & Network Logs',
                    icon: Icon(Icons.bug_report_outlined, size: 18)),
              ],
            ),
            const SizedBox(height: 16),

            // Tab Views
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildServerConnectionTab(),
                  _buildErrorLogsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerConnectionTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current Status Banner
          ValueListenableBuilder<bool>(
            valueListenable: AppConfig.instance.serverHealthyNotifier,
            builder: (context, isHealthy, _) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isHealthy
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: isHealthy
                          ? const Color(0xFFBBF7D0)
                          : const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isHealthy
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      color: isHealthy
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isHealthy
                                ? 'Backend Server Online'
                                : 'Backend Server Unreachable',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isHealthy
                                  ? const Color(0xFF166534)
                                  : const Color(0xFF991B1B),
                            ),
                          ),
                          ValueListenableBuilder<String>(
                            valueListenable: AppConfig.instance.baseUrlNotifier,
                            builder: (context, url, _) => Text(
                              'Target: $url',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: isHealthy
                                      ? const Color(0xFF166534)
                                      : const Color(0xFF991B1B)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0F766E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      onPressed: _isTesting
                          ? null
                          : () => _applyUrl(_urlController.text.trim()),
                      icon: _isTesting
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.refresh, size: 14),
                      label: const Text('Ping', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          const Text('1-Click Connection Presets:',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1C1917))),
          const SizedBox(height: 10),

          // Presets Buttons
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildPresetCard(
                title: 'Wi-Fi LAN IP (Real Phones)',
                url: AppConfig.defaultWifiLan,
                subtitle: 'Recommended for physical phones on same Wi-Fi',
                icon: Icons.wifi,
              ),
              _buildPresetCard(
                title: 'Android Emulator',
                url: AppConfig.defaultEmulator,
                subtitle:
                    'Maps 10.0.2.2 to host PC (Android Studio/Genymotion)',
                icon: Icons.phone_android,
              ),
              _buildPresetCard(
                title: 'Localhost / ADB Reverse',
                url: AppConfig.defaultLocalhost,
                subtitle: 'For Web Browser or phone over USB adb reverse',
                icon: Icons.computer,
              ),
            ],
          ),
          const SizedBox(height: 20),

          const Text('Custom Server URL:',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1C1917))),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g. http://192.168.1.14:8000',
                    prefixIcon: const Icon(Icons.link,
                        size: 18, color: Color(0xFF78716C)),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE6E4E0))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE6E4E0))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: Color(0xFF0F766E), width: 2)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F766E),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _isTesting
                    ? null
                    : () => _applyUrl(_urlController.text.trim()),
                child: const Text('Save & Apply',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),

          if (_testResult != null) ...[
            const SizedBox(height: 10),
            Text(
              _testResult!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _testResult!.contains('success')
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFDC2626),
              ),
            ),
          ],

          const SizedBox(height: 20),
          const Divider(color: Color(0xFFE6E4E0)),
          const SizedBox(height: 12),
          const Text('In-App Direct OTA Updates:',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1C1917))),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6E4E0)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0FDF9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.system_update_alt_rounded,
                      color: Color(0xFF0F766E), size: 20),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Check for New Builds',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1C1917))),
                      SizedBox(height: 2),
                      Text('Download & install updates directly from server',
                          style: TextStyle(
                              fontSize: 11, color: Color(0xFF78716C))),
                    ],
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F766E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    AppUpdater.instance
                        .checkForUpdates(context, showNoUpdateDialog: true);
                  },
                  child: const Text('Check Now',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetCard(
      {required String title,
      required String url,
      required String subtitle,
      required IconData icon}) {
    return ValueListenableBuilder<String>(
      valueListenable: AppConfig.instance.baseUrlNotifier,
      builder: (context, currentUrl, _) {
        final isSelected = currentUrl == url;

        return InkWell(
          onTap: () => _applyUrl(url),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFF0FDF9) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF0F766E)
                    : const Color(0xFFE6E4E0),
                width: isSelected ? 2.0 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Icon(icon,
                    color: isSelected
                        ? const Color(0xFF0F766E)
                        : const Color(0xFF78716C),
                    size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(title,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isSelected
                                      ? const Color(0xFF0F766E)
                                      : const Color(0xFF1C1917))),
                          if (isSelected) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.check_circle,
                                color: Color(0xFF0F766E), size: 14),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(url,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11.5,
                              color: Color(0xFF0F766E),
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF78716C))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildErrorLogsTab() {
    final logs = DebugLogger.instance.logs;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Captured Events (${logs.length}):',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            Row(
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copy All', style: TextStyle(fontSize: 12)),
                  onPressed: logs.isEmpty
                      ? null
                      : () {
                          final text = logs
                              .map((l) =>
                                  '[${l.timestamp.toIso8601String()}] [${l.type.name.toUpperCase()}] ${l.title}\nDetails: ${l.details ?? ""}\nStack: ${l.stackTrace ?? ""}')
                              .join('\n---\n');
                          Clipboard.setData(ClipboardData(text: text));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text(
                                      'Diagnostics logs copied to clipboard!')));
                        },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline,
                      size: 14, color: Colors.red),
                  label: const Text('Clear',
                      style: TextStyle(fontSize: 12, color: Colors.red)),
                  onPressed: () {
                    DebugLogger.instance.clearLogs();
                    setState(() {});
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: logs.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: Color(0xFF10B981), size: 36),
                      SizedBox(height: 8),
                      Text('No errors or warnings recorded.',
                          style: TextStyle(
                              color: Color(0xFF78716C), fontSize: 13)),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: logs.reversed.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final log = logs.reversed.toList()[index];
                    Color badgeColor;
                    IconData badgeIcon;

                    switch (log.type) {
                      case LogType.error:
                        badgeColor = const Color(0xFFDC2626);
                        badgeIcon = Icons.error;
                        break;
                      case LogType.warning:
                        badgeColor = const Color(0xFFD97706);
                        badgeIcon = Icons.warning_amber_rounded;
                        break;
                      case LogType.network:
                        badgeColor = const Color(0xFF0F766E);
                        badgeIcon = Icons.http;
                        break;
                      case LogType.info:
                        badgeColor = const Color(0xFF4F46E5);
                        badgeIcon = Icons.info_outline;
                    }

                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE6E4E0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(badgeIcon, color: badgeColor, size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  log.title,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color: badgeColor),
                                ),
                              ),
                              Text(
                                '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                    fontSize: 10.5, color: Color(0xFF78716C)),
                              ),
                            ],
                          ),
                          if (log.details != null &&
                              log.details!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              log.details!,
                              style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  color: Color(0xFF1C1917)),
                            ),
                          ],
                          if (log.stackTrace != null &&
                              log.stackTrace!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E38),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text(
                                log.stackTrace!,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 10,
                                    color: Colors.white70),
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
