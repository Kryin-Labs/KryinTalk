import '../supabase/supabase_service.dart';
import 'attachment_download_stub.dart'
    if (dart.library.html) 'attachment_download_web.dart' as platform;

Future<Uri?> freshAttachmentUri(Uri uri,
    {String? storagePath, Future<String?> Function(String)? signer}) async {
  String? path = storagePath;
  for (final marker in [
    '/storage/v1/object/sign/attachments/',
    '/storage/v1/object/public/attachments/'
  ]) {
    final at = uri.path.indexOf(marker);
    if (path == null && at >= 0) {
      path = Uri.decodeComponent(uri.path.substring(at + marker.length));
      break;
    }
  }
  if (path == null) return uri;
  final signed = await (signer ??
      (path) => SupabaseService.instance
          .createSignedUrl(bucket: 'attachments', path: path))(path);
  return signed == null || signed.isEmpty ? null : Uri.tryParse(signed);
}

Future<bool> downloadAttachment(Uri uri, String filename,
    {String? storagePath}) async {
  final fresh = await freshAttachmentUri(uri, storagePath: storagePath);
  return fresh != null && await platform.downloadAttachment(fresh, filename);
}
