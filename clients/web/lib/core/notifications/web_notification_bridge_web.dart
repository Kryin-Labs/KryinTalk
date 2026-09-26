import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSObject? get _notifications {
  final value = globalContext['connectHubNotifications'];
  return value is JSObject ? value : null;
}

void requestPermission() {
  _notifications?.callMethod<JSAny?>('requestPermission'.toJS);
}

void show(String title, String body, String tag, String icon) {
  _notifications?.callMethod<JSAny?>(
    'showNotification'.toJS,
    title.toJS,
    body.toJS,
    tag.toJS,
    icon.toJS,
  );
}
