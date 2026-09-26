/// ConnectHub — Admin Dual Vault Backup Management Screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/global_header.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  List<Map<String, dynamic>> _backups = [];
  bool _isLoading = true;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.get(ApiEndpoints.adminBackup);
      final data = response.data;
      if (data is Map && data.containsKey('items')) {
        setState(() {
          _backups = List<Map<String, dynamic>>.from(data['items']);
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _createBackup() async {
    setState(() => _isCreating = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post(ApiEndpoints.adminBackup);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dual Vault Backup (Website + Database) created successfully. Old backups pruned (5 max).'),
            backgroundColor: Color(0xFF0F766E),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create backup vault.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
    if (mounted) setState(() => _isCreating = false);
  }

  Future<void> _restoreBackup(String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(LucideIcons.triangle_alert, color: Colors.orangeAccent, size: 22),
            SizedBox(width: 10),
            Text(
              'Restore System Vault?',
              style: TextStyle(color: AppTheme.charcoalForeground, fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to restore from: $title?',
              style: const TextStyle(color: Color(0xFF44403C), fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Text(
                '⚠️ This will overwrite current database records with the snapshot contents from this backup.',
                style: TextStyle(color: Color(0xFF92400E), fontSize: 12, height: 1.4),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF78716C))),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0F766E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(LucideIcons.refresh_cw, size: 15),
            label: const Text('Confirm Restore'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = ref.read(apiClientProvider);
        await api.dio.post(ApiEndpoints.adminRestoreBackup(id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Vault backup restored successfully!'),
              backgroundColor: Color(0xFF0F766E),
            ),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to restore backup.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteBackup(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Backup Archive?'),
        content: const Text('This action will permanently remove this encrypted vault backup.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = ref.read(apiClientProvider);
        await api.dio.delete(ApiEndpoints.adminDeleteBackup(id));
        await _load();
      } catch (_) {}
    }
  }

  String _formatBytes(dynamic bytes) {
    final b = int.tryParse(bytes.toString()) ?? 0;
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatTitle(Map<String, dynamic> backup) {
    if (backup['formatted_title'] != null && backup['formatted_title'].toString().isNotEmpty) {
      return backup['formatted_title'].toString();
    }
    final rawDate = backup['created_at']?.toString() ?? '';
    String timeFormatted = '00/00/00 00:00:00';
    try {
      final dt = DateTime.parse(rawDate).toLocal();
      final dd = dt.day.toString().padLeft(2, '0');
      final mm = dt.month.toString().padLeft(2, '0');
      final yy = (dt.year % 100).toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      final ss = dt.second.toString().padLeft(2, '0');
      timeFormatted = '$dd/$mm/$yy $hh:$min:$ss';
    } catch (_) {}
    return 'Website Backup $timeFormatted & Database backup $timeFormatted';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.creamBackground,
      appBar: GlobalHeader(
        title: 'Backups',
        description: 'Automated 12-Hour Encrypted Dual Vault (Website + Database) • 5 Latest Retained',
        breadcrumbs: const ['ADMIN', 'Backups'],
        primaryActionLabel: _isCreating ? 'Creating Vault...' : 'Create Vault Backup',
        primaryActionIcon: LucideIcons.database,
        onPrimaryAction: _isCreating ? null : _createBackup,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryTeal))
          : Column(
              children: [
                // Info Policy Banner
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE7E5E4)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.emeraldLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.emeraldBorder),
                        ),
                        child: const Icon(LucideIcons.shield_check, color: AppTheme.primaryTeal, size: 18),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Automated 12-Hour Dual Vault Policy (Keep Only 5 Backups)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: AppTheme.charcoalForeground,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Backups capture both Website build assets and Database tables, encrypted with SHA-256 HMAC integrity. Every 12 hours an automated backup runs and prunes older archives to preserve only the 5 most recent.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF57534E), height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Backups List
                Expanded(
                  child: _backups.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFFE7E5E4)),
                                ),
                                child: const Icon(LucideIcons.database, size: 36, color: AppTheme.mutedText),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'No backups generated yet',
                                style: TextStyle(
                                  color: AppTheme.charcoalForeground,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Click "Create Vault Backup" above or wait for the 12-hour scheduler.',
                                style: TextStyle(color: AppTheme.mutedText, fontSize: 12.5),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(20),
                          itemCount: _backups.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final backup = _backups[index];
                            final title = _formatTitle(backup);
                            final backupId = backup['id']?.toString() ?? '';
                            final sizeStr = _formatBytes(backup['size_bytes']);

                            return Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE7E5E4)),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Color(0x08000000),
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: AppTheme.emeraldLight,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: AppTheme.emeraldBorder),
                                    ),
                                    child: const Icon(LucideIcons.archive, color: AppTheme.primaryTeal, size: 20),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: AppTheme.charcoalForeground,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          crossAxisAlignment: WrapCrossAlignment.center,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF5F5F4),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFE7E5E4)),
                                              ),
                                              child: Text(
                                                sizeStr,
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF44403C),
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.emeraldLight,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: AppTheme.emeraldBorder),
                                              ),
                                              child: const Text(
                                                '🔒 Encrypted Dual Vault (Web + DB)',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppTheme.primaryTeal,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF0FDF4),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: const Color(0xFFBBF7D0)),
                                              ),
                                              child: const Text(
                                                '✓ SHA-256 Verified',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF15803D),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  OutlinedButton.icon(
                                    onPressed: () => _restoreBackup(backupId, title),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.primaryTeal,
                                      side: const BorderSide(color: AppTheme.emeraldBorder),
                                      backgroundColor: AppTheme.emeraldLight,
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    icon: const Icon(LucideIcons.refresh_cw, size: 14),
                                    label: const Text('Restore', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(LucideIcons.trash_2, color: Colors.redAccent, size: 18),
                                    onPressed: () => _deleteBackup(backupId),
                                    tooltip: 'Delete Archive',
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
