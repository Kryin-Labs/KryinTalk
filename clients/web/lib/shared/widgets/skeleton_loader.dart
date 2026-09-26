import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../../core/theme/app_theme.dart';

/// Reusable shimmer-animated skeleton components for premium loading states.
class SkeletonLoader extends StatelessWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;

  const SkeletonLoader({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = baseColor ?? (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9));
    final highlight = highlightColor ?? (isDark ? const Color(0xFF334155) : const Color(0xFFFFFFFF));

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      period: const Duration(milliseconds: 1400),
      child: child,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double? width;
  final double? height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class SkeletonCircle extends StatelessWidget {
  final double radius;

  const SkeletonCircle({
    super.key,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Skeleton for a single conversation in the sidebar
class SkeletonConversationItem extends StatelessWidget {
  const SkeletonConversationItem({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const SkeletonCircle(radius: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    SkeletonBox(width: 110, height: 14, borderRadius: 4),
                    SkeletonBox(width: 45, height: 11, borderRadius: 4),
                  ],
                ),
                const SizedBox(height: 8),
                const SkeletonBox(width: 160, height: 12, borderRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Skeleton list for conversations
class SkeletonConversationList extends StatelessWidget {
  final int count;
  const SkeletonConversationList({super.key, this.count = 6});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: Column(
        children: List.generate(count, (_) => const SkeletonConversationItem()),
      ),
    );
  }
}

/// Skeleton chat message bubble
class SkeletonMessageBubble extends StatelessWidget {
  final bool isMe;
  final double bubbleWidth;

  const SkeletonMessageBubble({
    super.key,
    this.isMe = false,
    this.bubbleWidth = 220,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            const SkeletonCircle(radius: 16),
            const SizedBox(width: 10),
          ],
          Container(
            width: bubbleWidth,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMe ? 16 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                SkeletonBox(width: bubbleWidth * 0.9, height: 13, borderRadius: 4),
                const SizedBox(height: 8),
                SkeletonBox(width: bubbleWidth * 0.6, height: 13, borderRadius: 4),
                const SizedBox(height: 8),
                SkeletonBox(width: 40, height: 9, borderRadius: 3),
              ],
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 10),
            const SkeletonCircle(radius: 16),
          ],
        ],
      ),
    );
  }
}

/// Skeleton view for loading chat messages
class SkeletonChatView extends StatelessWidget {
  const SkeletonChatView({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: const [
          SkeletonMessageBubble(isMe: false, bubbleWidth: 260),
          SkeletonMessageBubble(isMe: false, bubbleWidth: 180),
          SkeletonMessageBubble(isMe: true, bubbleWidth: 220),
          SkeletonMessageBubble(isMe: true, bubbleWidth: 150),
          SkeletonMessageBubble(isMe: false, bubbleWidth: 290),
          SkeletonMessageBubble(isMe: true, bubbleWidth: 240),
        ],
      ),
    );
  }
}

/// Skeleton view for Dashboard stat cards
class SkeletonDashboardCard extends StatelessWidget {
  const SkeletonDashboardCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              SkeletonBox(width: 90, height: 13, borderRadius: 4),
              SkeletonCircle(radius: 18),
            ],
          ),
          const SizedBox(height: 16),
          const SkeletonBox(width: 70, height: 28, borderRadius: 6),
          const SizedBox(height: 10),
          const SkeletonBox(width: 130, height: 11, borderRadius: 4),
        ],
      ),
    );
  }
}

/// Skeleton for User Directory Card
class SkeletonUserCard extends StatelessWidget {
  const SkeletonUserCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const SkeletonCircle(radius: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 120, height: 14, borderRadius: 4),
                SizedBox(height: 6),
                SkeletonBox(width: 80, height: 11, borderRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
