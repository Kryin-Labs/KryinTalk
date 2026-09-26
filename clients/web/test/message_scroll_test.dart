import 'package:connecthub_web/features/messaging/message_scroll.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reply jump reveals exact row across mixed message heights',
      (tester) async {
    final controller = ScrollController();
    final ids = List.generate(80, (index) => 'message-$index');
    final keys = <String, GlobalKey>{};
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 360,
          child: ListView.builder(
            controller: controller,
            itemCount: ids.length,
            itemBuilder: (_, index) => SizedBox(
              key: keys.putIfAbsent(ids[index], () => GlobalKey()),
              height: index.isEven ? 48 : 170,
              child: Text(ids[index]),
            ),
          ),
        ),
      ),
    ));
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    final result = revealMessage(
      controller: controller,
      messageIds: ids,
      keys: keys,
      targetId: 'message-7',
      isCurrent: () => true,
    );
    await tester.pumpAndSettle();
    expect(await result, isTrue);
    final target = tester.getRect(find.text('message-7'));
    expect(target.top, greaterThanOrEqualTo(0));
    expect(target.bottom, lessThanOrEqualTo(360));

    final forward = revealMessage(
      controller: controller,
      messageIds: ids,
      keys: keys,
      targetId: 'message-71',
      isCurrent: () => true,
    );
    await tester.pumpAndSettle();
    expect(await forward, isTrue);
    final later = tester.getRect(find.text('message-71'));
    expect(later.top, greaterThanOrEqualTo(0));
    expect(later.bottom, lessThanOrEqualTo(360));
    controller.dispose();
  });
}
