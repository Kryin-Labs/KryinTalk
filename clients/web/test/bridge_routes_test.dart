import 'package:flutter_test/flutter_test.dart';
import 'package:connecthub_web/core/api/api_endpoints.dart';
import 'package:connecthub_web/core/api/bridge_routes.dart';

void main() {
  const collection = '/messaging/conversations/conversation-1/messages';

  test('message collection cannot swallow message writes or reactions', () {
    expect(BridgeRoutes.messageCollection.firstMatch(collection)?.group(1),
        'conversation-1');
    for (final suffix in [
      '/message-1',
      '/message-1/pin',
      '/message-1/reactions/%F0%9F%91%8D',
      '/message-1/reactions'
    ]) {
      expect(BridgeRoutes.messageCollection.hasMatch('$collection$suffix'),
          isFalse,
          reason: suffix);
    }
  });

  test('message actions retain conversation, message and encoded emoji', () {
    final reaction = BridgeRoutes.messageAction
        .firstMatch('$collection/message-1/reactions/%F0%9F%91%8D')!;
    expect(reaction.group(1), 'conversation-1');
    expect(reaction.group(2), 'message-1');
    expect(reaction.group(3), 'reactions');
    expect(Uri.decodeComponent(reaction.group(4)!), '👍');
    final pin =
        BridgeRoutes.messageAction.firstMatch('$collection/message-1/pin')!;
    expect(pin.group(3), 'pin');
    final item =
        BridgeRoutes.messageAction.firstMatch('$collection/message-1')!;
    expect(item.group(3), isNull);
    expect(
        BridgeRoutes.messageAction
            .hasMatch('$collection/message-1/pin/extra/path'),
        isFalse);
  });

  test('production requests are never pointed at the retired local API', () {
    final productionBase = Uri.parse(ApiEndpoints.baseUrl);
    expect(productionBase.scheme, 'https');
    expect(productionBase.host, endsWith('.supabase.co'));
    expect(ApiEndpoints.baseUrl, isNot(contains('localhost')));
  });
}
