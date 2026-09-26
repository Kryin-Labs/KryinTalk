import 'package:flutter/material.dart';

/// Reveals a lazily built message even when earlier messages have mixed heights.
Future<bool> revealMessage({
  required ScrollController controller,
  required List<String> messageIds,
  required Map<String, GlobalKey> keys,
  required String targetId,
  required bool Function() isCurrent,
}) async {
  final targetIndex = messageIds.indexOf(targetId);
  if (targetIndex < 0 || !controller.hasClients) return false;

  Future<bool> revealIfBuilt() async {
    final context = keys[targetId]?.currentContext;
    if (context == null || !isCurrent()) return false;
    await Scrollable.ensureVisible(context,
        alignment: 0.25,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubic);
    return true;
  }

  if (await revealIfBuilt()) return true;
  final position = controller.position;
  controller.jumpTo(position.maxScrollExtent *
      targetIndex /
      (messageIds.length > 1 ? messageIds.length - 1 : 1));
  await WidgetsBinding.instance.endOfFrame;

  // A proportional offset is only a starting point. Scan by less than a
  // viewport so a tall Markdown or attachment row cannot be skipped.
  while (controller.hasClients && isCurrent()) {
    if (await revealIfBuilt()) return true;
    var first = messageIds.length;
    var last = -1;
    for (var i = 0; i < messageIds.length; i++) {
      if (keys[messageIds[i]]?.currentContext != null) {
        if (i < first) first = i;
        last = i;
      }
    }
    if (last < 0) return false;
    final direction = targetIndex < first
        ? -1
        : targetIndex > last
            ? 1
            : 0;
    if (direction == 0) return false;
    final current = controller.position;
    final next = (current.pixels + direction * current.viewportDimension * 0.7)
        .clamp(current.minScrollExtent, current.maxScrollExtent)
        .toDouble();
    if (next == current.pixels) return false;
    controller.jumpTo(next);
    await WidgetsBinding.instance.endOfFrame;
  }
  return false;
}
