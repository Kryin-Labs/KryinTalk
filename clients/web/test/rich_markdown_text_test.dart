import 'package:connecthub_web/shared/widgets/rich_markdown_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('HTML-looking code stays visible beside Markdown formatting',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RichMarkdownText(text: '<h1>\n**bold**\n`<div>`'),
      ),
    ));
    final visible = [
      ...tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? ''),
      ...tester
          .widgetList<RichText>(find.byType(RichText))
          .map((widget) => widget.text.toPlainText()),
      ...tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? ''),
    ].join(' ');
    expect(visible, contains('<h1>'));
    expect(visible, contains('bold'));
    expect(visible, contains('<div>'));
  });

  testWidgets('Windows Markdown files keep headings, lists and fenced code',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RichMarkdownText(
            text: '# Notes\r\n\r\n- first\r\n- second\r\n\r\n'
                '```html\r\n<h1>Hi</h1>\r\n```'),
      ),
    ));
    final visible = [
      ...tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? ''),
      ...tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? ''),
    ].join(' ');
    expect(visible, contains('Notes'));
    expect(visible, contains('first'));
    expect(visible, contains('second'));
    expect(visible, contains('<h1>Hi</h1>'));
  });

  testWidgets('email addresses and URLs keep their @ characters',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RichMarkdownText(
            text: 'Contact [me](mailto:me@example.com) or visit '
                'https://example.com/@team and ping @alice.'),
      ),
    ));
    final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(markdown.data, contains('mailto:me@example.com'));
    expect(markdown.data, contains('https://example.com/@team'));
    expect(markdown.data, contains('[@alice](mention:@alice)'));
  });
}
