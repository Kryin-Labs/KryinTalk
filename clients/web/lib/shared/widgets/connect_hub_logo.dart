/// KryinTalk's theme-aware brand mark and wordmark.
library;

import 'package:flutter/material.dart';

class KryinTalkLogo extends StatelessWidget {
  final double size;
  final bool showText;
  final double textSize;
  final Color? iconColor;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const KryinTalkLogo({
    super.key,
    this.size = 38,
    this.showText = false,
    this.textSize = 20,
    this.iconColor,
    this.backgroundColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.circular(size * 0.32);

    final logoIcon = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.primary,
        borderRadius: borderRadius,
        border: Border.all(
          color: colors.outlineVariant,
          width: 1.0,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.forum_rounded,
          color: iconColor ?? colors.onPrimary,
          size: size * 0.58,
        ),
      ),
    );

    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        logoIcon,
        if (showText) ...[
          const SizedBox(width: 12),
          Flexible(child: Text(
            'KryinTalk',
            style: TextStyle(
              fontSize: textSize,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
              letterSpacing: -0.5,
            ),
          )),
        ],
      ],
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: showText ? BorderRadius.circular(12) : borderRadius,
        child: content,
      );
    }

    return content;
  }
}
