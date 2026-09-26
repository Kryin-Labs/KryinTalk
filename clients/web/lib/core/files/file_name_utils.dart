/// Helpers for keeping uploaded filenames safe and user-friendly.

import 'dart:convert';
import 'dart:typed_data';

/// Show small Markdown attachments in chat while keeping the original file.
/// ponytail: 32 KiB inline limit; stream a preview if larger files need rendering.
String attachmentMessageContent(String filename, Uint8List bytes) {
  if (!RegExp(r'\.(md|markdown)$', caseSensitive: false).hasMatch(filename) ||
      bytes.length > 32 * 1024) {
    return filename;
  }
  try {
    final markdown = utf8.decode(bytes).trim();
    return markdown.isEmpty ? filename : markdown;
  } on FormatException {
    return filename;
  }
}

/// Returns the original filename from a stored path or public URL.
///
/// Older uploads used paths such as `conv_<id>_<timestamp>_<filename>`.
/// New uploads keep the filename as the final URL segment, but this also
/// cleans those legacy names so they remain readable in the UI and downloads.
String cleanAttachmentName(Object? raw, {String fallback = 'Attachment'}) {
  var value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return fallback;

  value = value.replaceAll('\\', '/');
  final looksLikeUrl = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(value);
  final parsed = looksLikeUrl ? Uri.tryParse(value) : null;
  if (parsed != null && parsed.pathSegments.isNotEmpty) {
    value = parsed.pathSegments.last;
  } else if (value.contains('/')) {
    value = value.split('/').last;
  }

  try {
    value = Uri.decodeComponent(value);
  } catch (_) {
    // Keep the raw segment when a legacy URL contains malformed escaping.
  }

  final legacyPrefix = RegExp(r'^(?:conv|global)_[^_]+_\d+_(.+)$');
  final match = legacyPrefix.firstMatch(value);
  if (match != null) value = match.group(1)!;

  return value.isEmpty ? fallback : value;
}

/// Sanitizes a local filename before it is used as a storage object name.
String storageSafeFileName(String raw) {
  final value = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      .replaceAll(RegExp(r'\s+'), '_')
      .trim();
  return value.isEmpty ? 'attachment' : value;
}
