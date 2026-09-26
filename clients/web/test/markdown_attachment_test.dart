import 'dart:convert';
import 'dart:typed_data';

import 'package:connecthub_web/core/files/file_name_utils.dart';
import 'package:connecthub_web/core/supabase/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:connecthub_web/core/files/attachment_download.dart';

void main() {
  test('download mints a fresh URL and never falls back after signing fails',
      () async {
    final stale = Uri.parse(
        'https://project.supabase.co/storage/v1/object/sign/attachments/conversations/id/note.md?token=expired');
    String? path;
    final fresh = await freshAttachmentUri(stale, signer: (value) async {
      path = value;
      return 'https://project.supabase.co/fresh';
    });
    expect(path, 'conversations/id/note.md');
    expect(fresh.toString(), 'https://project.supabase.co/fresh');
    expect(await freshAttachmentUri(stale, signer: (_) async => null), isNull);
  });
  test('small Markdown files send formatted text and retain the attachment',
      () {
    final markdown = '# Notes\r\n\r\n```html\r\n<h1>Hi</h1>\r\n```';
    expect(
        attachmentMessageContent(
            'notes.MD', Uint8List.fromList(utf8.encode(markdown))),
        markdown.trim());
    expect(SupabaseService.getContentType('notes.MD'), 'text/markdown');
    expect(
        attachmentMessageContent(
            'notes.txt', Uint8List.fromList(utf8.encode(markdown))),
        'notes.txt');
    expect(attachmentMessageContent('large.md', Uint8List(32 * 1024 + 1)),
        'large.md');
  });
}
