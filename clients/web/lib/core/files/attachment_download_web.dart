import 'dart:html' as html;

/// Starts a browser download while preserving the original attachment name.
Future<bool> downloadAttachment(Uri uri, String filename) async {
  try {
    // Fetching the bytes first makes the filename override work for
    // cross-origin Supabase URLs too (where the download attribute alone is
    // ignored by browsers).
    final response = await html.HttpRequest.request(
      uri.toString(),
      method: 'GET',
      responseType: 'blob',
    );
    final blob = response.response;
    final status = response.status;
    if (status != null && status >= 200 && status < 300 && blob is html.Blob) {
      final objectUrl = html.Url.createObjectUrlFromBlob(blob);
      _clickDownload(objectUrl, filename);
      html.Url.revokeObjectUrl(objectUrl);
      return true;
    }
  } catch (_) {
    // Fall back to opening the URL when a host does not expose CORS headers.
  }

  _clickDownload(uri.toString(), filename, openInNewTab: true);
  return true;
}

void _clickDownload(String href, String filename, {bool openInNewTab = false}) {
  final anchor = html.AnchorElement(href: href)
    ..download = filename
    ..target = openInNewTab ? '_blank' : '_self'
    ..style.display = 'none';
  html.document.body?.children.add(anchor);
  anchor.click();
  anchor.remove();
}
