/// Exact cloud routes: collection handlers must never consume item actions.
class BridgeRoutes {
  BridgeRoutes._();

  static final messageCollection =
      RegExp(r'^/messaging/conversations/([^/]+)/messages$');
  static final messageAction = RegExp(
    r'^/messaging/conversations/([^/]+)/messages/([^/]+)(?:/(pin|reactions)(?:/([^/]+))?)?$',
  );
}
