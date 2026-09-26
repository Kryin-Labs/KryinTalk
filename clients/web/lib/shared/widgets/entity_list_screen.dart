/// ConnectHub — Generic CRUD List Screen Builder.
///
/// Reusable list screen pattern for departments, teams, groups, channels.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

/// Generic entity list screen with create/edit/delete support.
class EntityListScreen extends ConsumerStatefulWidget {
  final String title;
  final String endpoint;
  final String entityName;
  final List<String> displayFields;
  final List<String> createFields;
  final IconData icon;

  const EntityListScreen({
    super.key,
    required this.title,
    required this.endpoint,
    required this.entityName,
    required this.displayFields,
    required this.createFields,
    required this.icon,
  });

  @override
  ConsumerState<EntityListScreen> createState() => _EntityListScreenState();
}

class _EntityListScreenState extends ConsumerState<EntityListScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.dio.get(widget.endpoint);
      final data = response.data;
      if (data is Map && data.containsKey('items')) {
        _items = List<Map<String, dynamic>>.from(data['items']);
      } else if (data is List) {
        _items = List<Map<String, dynamic>>.from(data);
      }
      _error = null;
    } catch (e) {
      _error = 'Failed to load ${widget.entityName}s';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _createItem() async {
    final result = await _showFormDialog(null);
    if (result != null) {
      try {
        final api = ref.read(apiClientProvider);
        await api.dio.post(widget.endpoint, data: result);
        _loadItems();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create ${widget.entityName}')),
          );
        }
      }
    }
  }

  Future<void> _deleteItem(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.entityName}?'),
        content: const Text('This action cannot be undone.'),
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
        await api.dio.delete('${widget.endpoint}/$id');
        _loadItems();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete ${widget.entityName}')),
          );
        }
      }
    }
  }

  Future<Map<String, dynamic>?> _showFormDialog(Map<String, dynamic>? existing) async {
    final controllers = <String, TextEditingController>{};
    for (final field in widget.createFields) {
      controllers[field] = TextEditingController(
        text: existing?[field]?.toString() ?? '',
      );
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Text(existing == null ? 'Create ${widget.entityName}' : 'Edit ${widget.entityName}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: controllers.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: e.value,
                    style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(labelText: _fieldLabel(e.key)),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final data = <String, dynamic>{};
                for (final e in controllers.entries) {
                  data[e.key] = e.value.text;
                }
                Navigator.pop(ctx, data);
              },
              child: Text(existing == null ? 'Create' : 'Save'),
            ),
          ],
        );
      },
    );
  }

  String _fieldLabel(String field) {
    return field.replaceAll('_', ' ').replaceFirstMapped(
      RegExp(r'^[a-z]'),
      (m) => m.group(0)!.toUpperCase(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadItems,
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _createItem,
            icon: const Icon(Icons.add, size: 18),
            label: Text('New ${widget.entityName}'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: Colors.redAccent.withValues(alpha: 0.5)),
                      const SizedBox(height: 12),
                      Text(_error!, style: TextStyle(color: Colors.white54)),
                      const SizedBox(height: 16),
                      OutlinedButton(onPressed: _loadItems, child: const Text('Retry')),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(widget.icon, size: 48, color: Colors.white24),
                          const SizedBox(height: 12),
                          Text('No ${widget.entityName}s yet', style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return Card(
                          child: ListTile(
                            leading: Icon(widget.icon, color: theme.colorScheme.primary),
                            title: Text(
                              item[widget.displayFields.first]?.toString() ?? '',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: widget.displayFields.length > 1
                                ? Text(item[widget.displayFields[1]]?.toString() ?? '')
                                : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                              onPressed: () => _deleteItem(item['id'].toString()),
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}
