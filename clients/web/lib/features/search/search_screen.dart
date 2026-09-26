/// ConnectHub — Upgraded Global Search Screen.
///
/// Features:
/// - Category Tabs: All, Messages, People, Files, Groups
/// - Submitted search & instant category filtering
/// - Clickable results with direct navigation to resources
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../shared/widgets/global_header.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  late TabController _categoryTabController;
  List<Map<String, dynamic>> _allResults = [];
  bool _isSearching = false;
  bool _hasSearched = false;
  int _searchRequest = 0;
  String _searchedQuery = '';
  List<String> _failedCategories = [];
  String _activeCategory = 'All';

  final List<String> _categories = [
    'All',
    'Messages',
    'People',
    'Files',
    'Groups',
  ];

  @override
  void initState() {
    super.initState();
    _categoryTabController =
        TabController(length: _categories.length, vsync: this);
    _categoryTabController.addListener(() {
      if (!_categoryTabController.indexIsChanging) {
        setState(
            () => _activeCategory = _categories[_categoryTabController.index]);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categoryTabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _items(dynamic data) {
    final items = data is Map ? data['items'] : data;
    if (items is! List) {
      throw const FormatException('Expected a list of search results');
    }
    return List<Map<String, dynamic>>.from(items);
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final request = ++_searchRequest;
    setState(() {
      _isSearching = true;
      _hasSearched = true;
      _searchedQuery = query;
      _failedCategories = [];
    });

    final api = ref.read(apiClientProvider);
    final results = <Map<String, dynamic>>[];
    final failures = <String>[];
    final normalizedQuery = query.toLowerCase();

    // Each source can fail independently without hiding successful results.
    Future<void> searchSource(List<String> categories,
        Future<List<Map<String, dynamic>>> Function() search) async {
      try {
        results.addAll(await search());
      } catch (_) {
        failures.addAll(categories);
      }
    }

    await Future.wait([
      searchSource(['Messages', 'Files'], () async {
        final response = await api.dio
            .get(ApiEndpoints.search, queryParameters: {'q': query});
        return _items(response.data).map((item) {
          final isMessage = item['result_type'] == 'message';
          final id = (item['resource_id'] ?? item['id'])?.toString();
          final conversationId = item['conversation_id']?.toString();
          return <String, dynamic>{
            'type': isMessage ? 'Messages' : 'Files',
            'title': item['title'] ?? 'Search Result',
            'snippet': item['snippet'] ?? '',
            'id': id,
            // A message without its location must not silently open the inbox.
            'path': isMessage
                ? (id != null &&
                        id.isNotEmpty &&
                        conversationId != null &&
                        conversationId.isNotEmpty
                    ? Uri(path: '/messages/$conversationId', queryParameters: {
                        'messageId': id,
                        'from': '/search',
                      }).toString()
                    : null)
                : '/files',
          };
        }).toList();
      }),
      searchSource(['People'], () async {
        final response = await api.dio.get(ApiEndpoints.directory);
        return _items(response.data)
            .where((user) {
              return (user['display_name']?.toString() ?? '')
                      .toLowerCase()
                      .contains(normalizedQuery) ||
                  (user['username']?.toString() ?? '')
                      .toLowerCase()
                      .contains(normalizedQuery);
            })
            .map((user) => <String, dynamic>{
                  'type': 'People',
                  'title': user['display_name'] ?? user['username'] ?? 'User',
                  'snippet': "@${user['username'] ?? ''}",
                  'id': user['id'],
                })
            .toList();
      }),
      for (final source in [
        ('Groups', ApiEndpoints.groups, '/groups'),
      ])
        searchSource([source.$1], () async {
          final response = await api.dio.get(source.$2);
          return _items(response.data)
              .where((item) => (item['name']?.toString() ?? '')
                  .toLowerCase()
                  .contains(normalizedQuery))
              .map((item) => <String, dynamic>{
                    'type': source.$1,
                    'title': item['name'] ?? '',
                    'snippet': item['description'] ?? source.$1,
                    'id': item['id'],
                    'path': source.$3,
                  })
              .toList();
        }),
    ]);

    if (!mounted || request != _searchRequest) return;
    // Keep category order stable even when network requests finish out of order.
    results.sort((a, b) => _categories
        .indexOf(a['type'])
        .compareTo(_categories.indexOf(b['type'])));
    setState(() {
      _allResults = results;
      _failedCategories = failures;
      _isSearching = false;
    });
  }

  Future<void> _openResult(Map<String, dynamic> result) async {
    try {
      if (result['type'] == 'People') {
        final userId = result['id']?.toString();
        if (userId == null || userId.isEmpty) {
          throw const FormatException('Missing user ID');
        }
        final response = await ref.read(apiClientProvider).dio.post(
          '${ApiEndpoints.conversations}/direct',
          data: {'recipient_id': userId},
        );
        final conversationId = response.data['id']?.toString();
        if (conversationId == null || conversationId.isEmpty) {
          throw const FormatException('Missing conversation ID');
        }
        if (mounted) context.go('/messages/$conversationId');
        return;
      }
      final path = result['path']?.toString();
      if (path == null) {
        throw const FormatException('Missing result location');
      }
      context.go(path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Could not open this result. Please try again.'),
        action: SnackBarAction(
            label: 'Retry', onPressed: () => _openResult(result)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final filteredResults = _activeCategory == 'All'
        ? _allResults
        : _allResults.where((r) => r['type'] == _activeCategory).toList();

    final failedCategories = _activeCategory == 'All'
        ? _failedCategories
        : _failedCategories.where((c) => c == _activeCategory).toList();

    return Scaffold(
      appBar: const GlobalHeader(
        title: 'Search',
        description: 'Global Enterprise Directory & Content Search',
        breadcrumbs: ['ConnectHub', 'Search'],
        showSearch: false,
      ),
      body: Column(
        children: [
          TabBar(
            controller: _categoryTabController,
            isScrollable: true,
            tabs: _categories.map((c) => Tab(text: c)).toList(),
          ),
          // Search Input Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: TextStyle(color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                hintText:
                    'Search messages, people, channels, files, departments...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _performSearch,
                ),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _performSearch(),
            ),
          ),

          if (!_isSearching && failedCategories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                  'Could not search ${failedCategories.join(', ')}. Try again.',
                )),
                TextButton(
                    onPressed: _performSearch, child: const Text('Retry')),
              ]),
            ),

          // Results Section
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : !_hasSearched
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.search, size: 54, color: Colors.white24),
                            SizedBox(height: 12),
                            Text('Type a query and press Enter to search',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 16)),
                          ],
                        ),
                      )
                    : filteredResults.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.find_in_page_outlined,
                                    size: 54, color: Colors.white24),
                                const SizedBox(height: 12),
                                Text(
                                    failedCategories.isNotEmpty
                                        ? 'Search results are unavailable for this query.'
                                        : 'No $_activeCategory results found for "$_searchedQuery"',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontSize: 15)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            itemCount: filteredResults.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final res = filteredResults[index];
                              final type = res['type']?.toString() ?? 'Result';

                              return Card(
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: theme.colorScheme.primary
                                        .withValues(alpha: 0.15),
                                    child: Icon(_iconForType(type),
                                        color: theme.colorScheme.primary),
                                  ),
                                  title: Text(res['title']?.toString() ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  subtitle: Text(
                                      res['snippet']?.toString() ?? '',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis),
                                  trailing: Chip(
                                    label: Text(type,
                                        style: const TextStyle(fontSize: 10)),
                                    backgroundColor: theme.colorScheme.primary
                                        .withValues(alpha: 0.1),
                                  ),
                                  onTap: () => _openResult(res),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'Messages':
        return Icons.chat_bubble_outline;
      case 'People':
        return Icons.person;
      case 'Files':
        return Icons.attach_file;
      case 'Groups':
        return Icons.group;
      default:
        return Icons.search;
    }
  }
}
