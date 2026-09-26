import 'package:url_launcher/url_launcher.dart';

/// Opens a file using the platform's normal external handler.
///
/// The web implementation sets an explicit download filename; this fallback
/// keeps mobile/desktop builds free of web-only APIs.
Future<bool> downloadAttachment(Uri uri, String filename) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
