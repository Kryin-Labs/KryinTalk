// Heartbeats arrive every 25 seconds. Allow missed beats; stale labels expire.
String effectivePresenceStatus(Map<String, dynamic> user, {DateTime? now}) {
  final status =
      (user['presence_status'] ?? user['status'])?.toString().toLowerCase();
  if (!['online', 'away', 'busy', 'dnd', 'focus'].contains(status))
    return 'offline';
  final heartbeat = DateTime.tryParse(
      (user['last_active_at'] ?? user['last_seen_at'])?.toString() ?? '');
  if (heartbeat == null) return 'offline';
  final age = (now ?? DateTime.now()).toUtc().difference(heartbeat.toUtc());
  return age >= const Duration(seconds: -30) &&
          age <= const Duration(seconds: 90)
      ? status!
      : 'offline';
}
