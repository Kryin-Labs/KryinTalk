/// ConnectHub — Live administration statistics dashboard.
library;

import 'package:flutter/material.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/supabase/supabase_service.dart';
import '../../shared/widgets/global_header.dart';
import '../../shared/widgets/skeleton_loader.dart';

class StatsDashboardScreen extends ConsumerStatefulWidget {
  const StatsDashboardScreen({super.key});

  @override
  ConsumerState<StatsDashboardScreen> createState() =>
      _StatsDashboardScreenState();
}

class _StatsDashboardScreenState extends ConsumerState<StatsDashboardScreen> {
  Map<String, num> _stats = const {};
  List<Map<String, dynamic>> _activity = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _load() async {
    if (mounted)
      setState(() {
        _loading = true;
        _error = null;
      });
    try {
      if (SupabaseService.instance.hasSession) {
        final client = SupabaseService.instance.client;
        final results = await Future.wait<dynamic>([
          client.from('users').select('id,is_active'),
          client.from('groups').select('id'),
          client.from('conversations').select('id'),
          client.from('messages').select('id,created_at'),
          client
              .from('file_attachments')
              .select('id,size_bytes')
              .isFilter('deleted_at', null),
          client
              .from('audit_logs')
              .select('id,action,created_at')
              .order('created_at', ascending: false)
              .limit(8),
        ]);
        final users = _rows(results[0]);
        final messages = _rows(results[3]);
        final files = _rows(results[4]);
        final now = DateTime.now();
        final messagesToday = messages.where((message) {
          final createdAt =
              DateTime.tryParse(message['created_at']?.toString() ?? '');
          return createdAt != null &&
              createdAt.year == now.year &&
              createdAt.month == now.month &&
              createdAt.day == now.day;
        }).length;
        _stats = {
          'total_users': users.length,
          'active_users':
              users.where((user) => user['is_active'] != false).length,
          'total_groups': _rows(results[1]).length,
          'total_conversations': _rows(results[2]).length,
          'total_messages': messages.length,
          'messages_today': messagesToday,
          'total_files': files.length,
          'total_file_bytes': files.fold<int>(
              0,
              (sum, file) =>
                  sum + ((file['size_bytes'] as num?)?.toInt() ?? 0)),
        };
        _activity = _rows(results[5]);
      } else {
        final response =
            await ref.read(apiClientProvider).dio.get(ApiEndpoints.adminStats);
        _stats = Map<String, dynamic>.from(response.data as Map)
            .map((key, value) => MapEntry(key, value is num ? value : 0));
      }
    } catch (error) {
      _error = 'Live statistics could not be loaded. ${error.toString()}';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatBytes(num bytes) {
    if (bytes >= 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    if (bytes >= 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${bytes.toInt()} B';
  }

  @override
  Widget build(BuildContext context) {
    final cards = <({String label, String value, IconData icon, Color color})>[
      (
        label: 'Active users',
        value: '${_stats['active_users'] ?? 0} / ${_stats['total_users'] ?? 0}',
        icon: LucideIcons.users,
        color: const Color(0xFF0F766E)
      ),
      (
        label: 'Messages today',
        value: '${_stats['messages_today'] ?? 0}',
        icon: LucideIcons.message_square_text,
        color: const Color(0xFF2563EB)
      ),
      (
        label: 'Conversations',
        value: '${_stats['total_conversations'] ?? 0}',
        icon: LucideIcons.messages_square,
        color: const Color(0xFF7C3AED)
      ),
      (
        label: 'Groups',
        value: '${_stats['total_groups'] ?? 0}',
        icon: LucideIcons.users_round,
        color: const Color(0xFFDB2777)
      ),
      (
        label: 'Stored files',
        value: '${_stats['total_files'] ?? 0}',
        icon: LucideIcons.files,
        color: const Color(0xFF4F46E5)
      ),
      (
        label: 'Storage used',
        value: _formatBytes(_stats['total_file_bytes'] ?? 0),
        icon: LucideIcons.hard_drive,
        color: const Color(0xFF059669)
      ),
    ];

    return Scaffold(
      appBar: GlobalHeader(
        title: 'Stats',
        description: 'Workspace health and usage',
        breadcrumbs: const ['ConnectHub', 'Administration', 'Stats'],
        primaryActionLabel: 'Refresh',
        primaryActionIcon: LucideIcons.refresh_cw,
        onPrimaryAction: _load,
      ),
      body: _loading
          ? GridView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: 8,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 320,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 2.1,
              ),
              itemBuilder: (context, index) => const SkeletonDashboardCard(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(LucideIcons.circle_alert,
                            color: Color(0xFFDC2626)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(_error!,
                                style:
                                    const TextStyle(color: Color(0xFF991B1B)))),
                        TextButton(
                            onPressed: _load, child: const Text('Retry')),
                      ]),
                    ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1050
                          ? 4
                          : constraints.maxWidth >= 620
                              ? 2
                              : 1;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: cards.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: columns == 1 ? 3.4 : 2.25,
                        ),
                        itemBuilder: (context, index) =>
                            _MetricCard(metric: cards[index]),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final health = _HealthCard(
                          totalMessages:
                              (_stats['total_messages'] ?? 0).toInt());
                      final activity = _ActivityCard(items: _activity);
                      if (constraints.maxWidth < 760) {
                        return Column(children: [
                          health,
                          const SizedBox(height: 14),
                          activity
                        ]);
                      }
                      return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: health),
                            const SizedBox(width: 14),
                            Expanded(flex: 2, child: activity),
                          ]);
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});
  final ({String label, String value, IconData icon, Color color}) metric;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Theme.of(context).dividerColor)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
                color: metric.color.withValues(alpha: .11),
                borderRadius: BorderRadius.circular(14)),
            child: Icon(metric.icon, color: metric.color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Text(metric.value,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800)),
                Text(metric.label,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
              ])),
        ]),
      ),
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({required this.totalMessages});
  final int totalMessages;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Theme.of(context).dividerColor)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Service health',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          _healthRow('Database', 'Connected'),
          _healthRow('Workspace API', 'Operational'),
          _healthRow('Indexed messages', '$totalMessages'),
        ]),
      ),
    );
  }

  Widget _healthRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          const SizedBox(
              width: 9,
              height: 9,
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: Color(0xFF10B981), shape: BoxShape.circle))),
          const SizedBox(width: 10),
          Expanded(child: Text(label)),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: Color(0xFF047857))),
        ]),
      );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.items});
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: Theme.of(context).dividerColor)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Recent system activity',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (items.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('No recent activity.')))
          else
            ...items.map((item) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                      radius: 16, child: Icon(LucideIcons.activity, size: 15)),
                  title: Text(
                      (item['action'] ?? 'Workspace activity')
                          .toString()
                          .replaceAll('.', ' '),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(item['created_at']?.toString() ?? 'Recently'),
                )),
        ]),
      ),
    );
  }
}
