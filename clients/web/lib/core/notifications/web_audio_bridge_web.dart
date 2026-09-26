import 'dart:js_interop';
import 'dart:js_interop_unsafe';

void invoke(String method) {
  final audio = globalContext['connectHubAudio'];
  if (audio is! JSObject) return;
  switch (method) {
    case 'playSentChime':
      audio.callMethod<JSAny?>('playSentChime'.toJS);
    case 'playReceivedChime':
      audio.callMethod<JSAny?>('playReceivedChime'.toJS);
  }
}
