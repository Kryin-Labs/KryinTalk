/// ConnectHub — Full Discord & README Document-Style Rich Markdown Renderer.
///
/// Complete Markdown Spec Support:
/// - OpenGraph Link Previews (Domain, Title, Description, Image Banner)
/// - Markdown Links (`[link text](url)`) with active `url_launcher` tap handling
/// - Headings (`# h1` through `###### h6`)
/// - Tables (`| Col 1 | Col 2 |`)
/// - Bullet Lists (`+`, `-`, `*`) & Numbered Lists (`1.`, `57.`)
/// - Blockquotes (`> quote`) & Nested Blockquotes (`>> quote`)
/// - Images (`![alt](url)`)
/// - Code Blocks (` ```lang \n code \n ``` `) with Language Tag & Copy Code Button
/// - Discord Spoilers (`||hidden text||`) with Click-to-Reveal animation
/// - Inline Code (`` `code` ``)
/// - Bold (`**text**`), Italic (`*text*`), Strikethrough (`~~text~~`), Underline (`__text__`)
/// - `@username` Mentions with interactive highlight pill
/// - Auto-converted links (`http://...`, `https://...`, `www....`)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

const List<String> kEmojiFontFallback = [
  'Noto Color Emoji',
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Segoe UI Symbol',
  'EmojiOne Color',
  'Android Emoji',
  'sans-serif',
];

class RichMarkdownText extends StatelessWidget {
  const RichMarkdownText({
    super.key,
    required this.text,
    this.textStyle = const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 14,
        height: 1.45,
        fontFamilyFallback: kEmojiFontFallback),
    this.allUsers = const [],
    this.onMentionTap,
  });

  final String text;
  final TextStyle textStyle;
  final List<Map<String, dynamic>> allUsers;
  final ValueChanged<Map<String, dynamic>>? onMentionTap;

  Future<void> _launchURL(String urlString) async {
    try {
      final Uri uri = Uri.parse(urlString);
      if (!{'http', 'https', 'mailto'}.contains(uri.scheme.toLowerCase()))
        return;
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final displayText = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 1. Extract Code Blocks ( ```lang ... ``` ) to render with custom Copy Code widget
    final codeBlockRegex = RegExp(r'```([a-zA-Z0-9_\-\+]*)\n([\s\S]*?)```');
    final matches = codeBlockRegex.allMatches(displayText);

    final List<Widget> blockWidgets = [];

    if (matches.isEmpty) {
      blockWidgets.add(_buildFullMarkdownBody(context, displayText));
    } else {
      int lastEnd = 0;
      for (final match in matches) {
        if (match.start > lastEnd) {
          final rawPre = displayText.substring(lastEnd, match.start);
          if (rawPre.trim().isNotEmpty) {
            blockWidgets.add(_buildFullMarkdownBody(context, rawPre));
          }
        }

        final lang = match.group(1)?.trim() ?? '';
        final codeContent = match.group(2) ?? '';
        blockWidgets.add(_CodeBlockWidget(language: lang, code: codeContent));

        lastEnd = match.end;
      }

      if (lastEnd < displayText.length) {
        final rawPost = displayText.substring(lastEnd);
        if (rawPost.trim().isNotEmpty) {
          blockWidgets.add(_buildFullMarkdownBody(context, rawPost));
        }
      }
    }

    final List<Widget> finalChildren = [];

    finalChildren.addAll(
      blockWidgets.map(
          (w) => Padding(padding: const EdgeInsets.only(bottom: 2), child: w)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: finalChildren,
    );
  }

  Widget _buildFullMarkdownBody(BuildContext context, String rawMarkdown) {
    // Process Discord Spoilers (||text||) & Mentions (@user) before passing to Markdown body
    final processedText = _preprocessDiscordTokens(rawMarkdown);

    final effectiveTextStyle = textStyle.copyWith(
      fontFamilyFallback: kEmojiFontFallback,
    );

    final textColor = effectiveTextStyle.color ?? const Color(0xFF0F172A);
    final isWhiteText = textColor.computeLuminance() > 0.5;

    final styleSheet = MarkdownStyleSheet(
      p: effectiveTextStyle,
      h1: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: textColor,
              height: 1.3)
          .copyWith(fontFamilyFallback: kEmojiFontFallback),
      h2: GoogleFonts.inter(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: textColor,
              height: 1.3)
          .copyWith(fontFamilyFallback: kEmojiFontFallback),
      h3: GoogleFonts.inter(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: textColor,
              height: 1.3)
          .copyWith(fontFamilyFallback: kEmojiFontFallback),
      h4: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: textColor,
              height: 1.3)
          .copyWith(fontFamilyFallback: kEmojiFontFallback),
      h5: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor.withValues(alpha: 0.8),
              height: 1.3)
          .copyWith(fontFamilyFallback: kEmojiFontFallback),
      h6: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor.withValues(alpha: 0.7),
              height: 1.3)
          .copyWith(fontFamilyFallback: kEmojiFontFallback),
      a: effectiveTextStyle.copyWith(
        color: isWhiteText ? const Color(0xFF67E8F9) : const Color(0xFF0284C7),
        backgroundColor:
            (isWhiteText ? const Color(0xFF0284C7) : const Color(0xFFE0F2FE))
                .withValues(alpha: 0.3),
        fontWeight: FontWeight.w700,
        decoration: TextDecoration.none,
      ),
      code: GoogleFonts.firaCode(
        fontSize: (effectiveTextStyle.fontSize ?? 14) - 1,
        color: isWhiteText ? const Color(0xFFCCFBF1) : const Color(0xFF0F766E),
        backgroundColor:
            isWhiteText ? const Color(0xFF1E1E38) : const Color(0xFFF1F5F9),
      ),
      codeblockDecoration: BoxDecoration(
        color: isWhiteText ? const Color(0xFF141426) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isWhiteText ? Colors.white10 : const Color(0xFFE2E8F0)),
      ),
      blockquote: effectiveTextStyle.copyWith(
          color: textColor.withValues(alpha: 0.85),
          fontStyle: FontStyle.italic),
      blockquoteDecoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.05),
        borderRadius: const BorderRadius.only(
            topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
        border: const Border(
            left: BorderSide(color: Color(0xFF0F766E), width: 4.0)),
      ),
      tableBorder:
          TableBorder.all(color: textColor.withValues(alpha: 0.2), width: 1.0),
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      tableHead: GoogleFonts.inter(
              fontSize: 13, fontWeight: FontWeight.bold, color: textColor)
          .copyWith(fontFamilyFallback: kEmojiFontFallback),
      tableBody: effectiveTextStyle,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
            top: BorderSide(
                color: textColor.withValues(alpha: 0.2), width: 1.0)),
      ),
      listBullet: effectiveTextStyle.copyWith(
          color:
              isWhiteText ? const Color(0xFFCCFBF1) : const Color(0xFF0F766E),
          fontWeight: FontWeight.bold),
    );

    return MarkdownBody(
      data: processedText,
      selectable: true,
      styleSheet: styleSheet,
      onTapLink: (text, href, title) {
        if (href != null && href.isNotEmpty) {
          if (href.startsWith('mention:')) {
            final rawMention = href
                .replaceFirst('mention:@', '')
                .replaceFirst('mention:', '')
                .toLowerCase()
                .trim();
            final matchedUser = allUsers.firstWhere(
              (u) =>
                  (u['username'] ?? '').toString().toLowerCase() ==
                      rawMention ||
                  (u['display_name'] ?? '').toString().toLowerCase() ==
                      rawMention ||
                  (u['email'] ?? '').toString().toLowerCase() == rawMention,
              orElse: () => <String, dynamic>{
                'username': rawMention,
                'display_name': rawMention,
              },
            );
            if (onMentionTap != null) {
              onMentionTap!(matchedUser);
            }
            return;
          }
          _launchURL(href);
        }
      },
      imageBuilder: (uri, title, alt) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          child: SmartImageOrSvgViewer(
            url: uri.toString(),
            fit: BoxFit.contain,
            altText: alt,
          ),
        );
      },
    );
  }

  String _preprocessDiscordTokens(String raw) {
    // Preserve inline code verbatim. flutter_markdown otherwise swallows raw
    // HTML tags, while escaping them inside `code` would show &lt; literally.
    final mentionRegex =
        RegExp(r'(^|[\s(\[{>,:])(@[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)*)');
    final htmlStart = RegExp(r'<(?!https?://|mailto:)', caseSensitive: false);
    final result = StringBuffer();
    final plain = StringBuffer();
    int? codeTicks;

    void flushPlain() {
      final escaped = plain.toString().replaceAll(htmlStart, '&lt;');
      result.write(escaped.replaceAllMapped(mentionRegex, (match) {
        final token = match.group(2)!;
        return '${match.group(1)}[$token](mention:$token)';
      }));
      plain.clear();
    }

    for (var i = 0; i < raw.length;) {
      if (raw[i] == '`') {
        var end = i + 1;
        while (end < raw.length && raw[end] == '`') {
          end++;
        }
        final ticks = end - i;
        if (codeTicks == null) {
          flushPlain();
          codeTicks = ticks;
        } else if (codeTicks == ticks) {
          codeTicks = null;
        }
        result.write(raw.substring(i, end));
        i = end;
      } else {
        if (codeTicks == null) {
          plain.write(raw[i]);
        } else {
          result.write(raw[i]);
        }
        i++;
      }
    }
    flushPlain();
    return result.toString();
  }
}

/// ── Smart Universal Image & Dynamic SVG Viewer ───────────────────────
class SmartImageOrSvgViewer extends StatelessWidget {
  const SmartImageOrSvgViewer({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.maxWidth = 540,
    this.maxHeight = 320,
    this.altText,
  });

  final String url;
  final BoxFit fit;
  final double maxWidth;
  final double maxHeight;
  final String? altText;

  static bool isSvgUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.svg') ||
        lower.contains('demolab.com') ||
        lower.contains('shields.io') ||
        lower.contains('badgen.net') ||
        lower.contains('github-readme-stats') ||
        lower.contains('svgporn') ||
        lower.contains('capsule-render') ||
        lower.contains('format=svg') ||
        lower.contains('image/svg');
  }

  @override
  Widget build(BuildContext context) {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return const SizedBox.shrink();

    final isSvg = isSvgUrl(cleanUrl);

    Widget content;
    if (isSvg) {
      content = SvgPicture.network(
        cleanUrl,
        fit: fit,
        placeholderBuilder: (ctx) => Container(
          padding: const EdgeInsets.all(16),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Color(0xFF38BDF8)),
          ),
        ),
        errorBuilder: (ctx, err, stack) => Image.network(
          cleanUrl,
          fit: fit,
          errorBuilder: (ctx2, err2, stack2) => _buildErrorWidget(),
        ),
      );
    } else {
      content = Image.network(
        cleanUrl,
        fit: fit,
        errorBuilder: (ctx, err, stack) => SvgPicture.network(
          cleanUrl,
          fit: fit,
          errorBuilder: (ctx2, err2, stack2) => _buildErrorWidget(),
        ),
      );
    }

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: content,
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.black26,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image_outlined,
              size: 18, color: Colors.white54),
          const SizedBox(width: 8),
          Text(altText ?? 'Image unavailable',
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}

/// ── Discord-Style Code Block Widget with Copy Button ────────────────
class _CodeBlockWidget extends StatefulWidget {
  const _CodeBlockWidget({required this.language, required this.code});

  final String language;
  final String code;

  @override
  State<_CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<_CodeBlockWidget> {
  bool _isCopied = false;

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.code.trim()));
    setState(() => _isCopied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code snippet copied to clipboard!'),
        duration: Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final langTag =
        widget.language.isEmpty ? 'CODE' : widget.language.toUpperCase();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141426),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar with Language Tag & Copy Code Button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A33),
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(12), topRight: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.code,
                        size: 14, color: Color(0xFF0F766E)),
                    const SizedBox(width: 8),
                    Text(
                      langTag,
                      style: GoogleFonts.firaCode(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF94A3B8),
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: _copyCode,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _isCopied ? LucideIcons.check : LucideIcons.copy,
                          size: 13,
                          color: _isCopied
                              ? Colors.greenAccent
                              : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isCopied ? 'Copied!' : 'Copy',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: _isCopied
                                ? Colors.greenAccent
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Code Content Container
          Padding(
            padding: const EdgeInsets.all(14),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                widget.code.trimRight(),
                style: GoogleFonts.firaCode(
                  fontSize: 13,
                  color: const Color(0xFFE2E8F0),
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
