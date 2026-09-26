/// ConnectHub — Admin Audit Log Viewer.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/auth/auth_service.dart';
import '../../shared/widgets/global_header.dart';

String auditActionLabel(String action) =>
    const {
      'access.approved': 'Access approved',
      'access.declined': 'Request declined',
      'access.reopened': 'Request reopened',
      'access.suspended': 'Access suspended',
      'access.restored': 'Access restored',
      'access.revoked': 'Access revoked',
      'role.changed': 'Application role changed',
      'account.pending_created': 'Account created',
      'account.consent_recorded': 'Account policies accepted',
      'invite.created': 'Access code issued',
      'invite.revoked': 'Access code revoked',
      'invite.redeemed': 'Access code redeemed',
      'invite.redeem_failed': 'Access code attempt failed',
    }[action] ??
    action;

class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});
  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  final _actionFilter = TextEditingController();
  String _resourceFilter = 'All';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _actionFilter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final params = <String, dynamic>{};
      if (_actionFilter.text.isNotEmpty) params['action'] = _actionFilter.text;
      if (_resourceFilter != 'All')
        params['resource_type'] = _resourceFilter.toLowerCase();
      final response = await api.dio
          .get(ApiEndpoints.adminAuditLogs, queryParameters: params);
      final data = response.data;
      if (data is Map && data.containsKey('items')) {
        _logs = List<Map<String, dynamic>>.from(data['items']);
      }
    } catch (error) {
      _error = AuthService.errorMessage(error);
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _showLogDetails(Map<String, dynamic> log) async {
    String pretty(dynamic value) {
      if (value == null) return '—';
      if (value is Map || value is List)
        return const JsonEncoder.withIndent('  ').convert(value);
      return value.toString();
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(children: [
          const Expanded(child: Text('Audit event details')),
          IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close)),
        ]),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _detail('Event ID', pretty(log['id'])),
              _detail('Action', auditActionLabel(pretty(log['action']))),
              _detail('Timestamp', pretty(log['created_at'])),
              _detail('Actor user ID', pretty(log['user_id'])),
              _detail('Resource',
                  '${pretty(log['resource_type'])} / ${pretty(log['resource_id'])}'),
              _detail('IP address', pretty(log['ip_address'])),
              _detail('User agent', pretty(log['user_agent'])),
              _detail('Details', pretty(log['details'])),
              _detail('Changes', pretty(log['changes'])),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          SelectableText(value),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const GlobalHeader(
        title: 'Logs',
        description: 'System Activity & Compliance History',
        breadcrumbs: ['ADMIN', 'Logs'],
      ),
      body: Column(
        children: [
          // Filter bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _actionFilter,
                    decoration: const InputDecoration(
                      hintText: 'Filter by action (e.g. admin.user.updated)',
                      prefixIcon: Icon(Icons.filter_list),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _resourceFilter,
                  items: const [
                    'All',
                    'User',
                    'Group',
                    'Message',
                    'File',
                    'Backup',
                    'App_access_invite'
                  ]
                      .map((value) =>
                          DropdownMenuItem(value: value, child: Text(value)))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _resourceFilter = value);
                    _load();
                  },
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _load, child: const Text('Filter')),
              ],
            ),
          ),

          // Logs
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _load, child: const Text('Retry')),
                      ]))
                    : _logs.isEmpty
                        ? const Center(child: Text('No audit logs found'))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _logs.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final log = _logs[index];
                              return Card(
                                child: ListTile(
                                  onTap: () => _showLogDetails(log),
                                  leading: Icon(Icons.receipt_long,
                                      color: theme.colorScheme.tertiary,
                                      size: 20),
                                  title: Text(
                                    auditActionLabel(
                                        log['action']?.toString() ?? ''),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    '${log['resource_type'] ?? ''} / ${log['resource_id'] ?? ''}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Text(
                                    log['created_at']
                                            ?.toString()
                                            .substring(0, 19) ??
                                        '',
                                    style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontSize: 11),
                                  ),
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
