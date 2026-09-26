import 'package:flutter_test/flutter_test.dart';
import 'package:connecthub_web/core/presence/presence_status.dart';

void main() {
  final now = DateTime.utc(2026, 9, 26, 12);
  Map<String, dynamic> record(String status, int age) => {
        'presence_status': status,
        'last_active_at': now.subtract(Duration(seconds: age)).toIso8601String()
      };
  test('online expires after 90 seconds, regardless of saved status', () {
    expect(effectivePresenceStatus(record('online', 25), now: now), 'online');
    expect(effectivePresenceStatus(record('online', 90), now: now), 'online');
    expect(effectivePresenceStatus(record('online', 91), now: now), 'offline');
    expect(
        effectivePresenceStatus(record('online', 86400), now: now), 'offline');
  });
  test('missing, invalid and far-future heartbeats never mean online', () {
    for (final value in [
      null,
      'invalid',
      now.add(const Duration(minutes: 5)).toIso8601String()
    ]) {
      expect(
          effectivePresenceStatus(
              {'presence_status': 'online', 'last_active_at': value},
              now: now),
          'offline');
    }
  });
  test('active custom statuses survive; offline and unknown statuses do not',
      () {
    for (final status in ['away', 'busy', 'dnd', 'focus'])
      expect(effectivePresenceStatus(record(status, 10), now: now), status);
    for (final status in ['offline', 'unknown'])
      expect(effectivePresenceStatus(record(status, 10), now: now), 'offline');
    expect(
        effectivePresenceStatus(
            {'status': 'away', 'last_seen_at': now.toIso8601String()},
            now: now),
        'away');
  });
}
