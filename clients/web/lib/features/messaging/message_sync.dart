import 'dart:async';

/// Serializes refreshes, retaining one trailing refresh when events arrive
/// during a request. Callers can await the whole refresh cycle.
class MessageRefresh {
  Future<void>? _running;
  bool _again = false;

  Future<void> run(Future<void> Function() refresh) {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    final completion = Completer<void>();
    _running = completion.future;
    () async {
      try {
        do {
          _again = false;
          await refresh();
        } while (_again);
        completion.complete();
      } catch (error, stack) {
        completion.completeError(error, stack);
      } finally {
        _running = null;
      }
    }();
    return completion.future;
  }
}

/// Keep pending sends and realtime changes that arrived after a fetch began.
/// Unchanged server rows absent from the snapshot are still removed.
List<Map<String, dynamic>> reconcileMessages(
  List<Map<String, dynamic>> snapshot,
  List<Map<String, dynamic>> current,
  List<Map<String, dynamic>> atRequestStart,
) {
  final baseline = {for (final row in atRequestStart) row['id']: row};
  final rows = {for (final row in snapshot) row['id']: row};
  for (final row in current) {
    final id = row['id'];
    if (id.toString().startsWith('temp_') ||
        !identical(baseline[id], row)) {
      rows[id] = row;
    }
  }
  return rows.values.toList()
    ..sort((a, b) => (a['created_at']?.toString() ?? '')
        .compareTo(b['created_at']?.toString() ?? ''));
}
