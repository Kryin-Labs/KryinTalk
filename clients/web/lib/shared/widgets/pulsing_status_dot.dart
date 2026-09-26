/// ConnectHub — Pulsing / Blinking Presence Status Dot.
///
/// Smoothly animates when user is active/online with their specific
/// presence status color (Emerald Green, Amber, Crimson Red, Deep Purple).
library;

import 'package:flutter/material.dart';

class PulsingStatusDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool isOnline;
  final bool pulse;

  const PulsingStatusDot({
    super.key,
    required this.color,
    this.size = 12,
    this.isOnline = true,
    this.pulse = true,
  });

  @override
  State<PulsingStatusDot> createState() => _PulsingStatusDotState();
}

class _PulsingStatusDotState extends State<PulsingStatusDot> with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    if (widget.isOnline && widget.pulse) {
      _animCtrl.repeat(reverse: true);
    }
    _animation = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(PulsingStatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOnline && widget.pulse) {
      if (!_animCtrl.isAnimating) _animCtrl.repeat(reverse: true);
    } else {
      _animCtrl.stop();
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isOnline) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: const Color(0xFF9CA3AF),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      );
    }

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: _animation.value),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.45 * _animation.value),
                blurRadius: 4,
                spreadRadius: 0.5,
              ),
            ],
          ),
        );
      },
    );
  }
}
