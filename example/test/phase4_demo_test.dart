import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_demo/main.dart';
import 'package:get_demo/phase4_demo.dart';

void main() {
  tearDown(Get.reset);

  Future<void> openDemo(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Phase4DemoPage()));
    await tester.pump();
  }

  /// The sections live in a lazy [ListView], so the lower ones are not built
  /// until they are scrolled into view.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
  }

  testWidgets('the demo is reachable from the home page', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.tap(find.text('GetBuilder / Get.find demo'));
    await tester.pumpAndSettle();

    expect(find.byType(Phase4DemoPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('1. update() during build does not throw', (tester) async {
    await openDemo(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('label: resolved during build'), findsOneWidget);

    // Resetting clears the label, so the next build resolves it again from
    // inside the build.
    await tester.tap(find.text('Reset and rebuild'));
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('label: resolved during build'), findsOneWidget);
  });

  testWidgets('2. Get.find reports a typed error', (tester) async {
    await openDemo(tester);

    await tester.tap(find.text('Find an unregistered controller'));
    await tester.pump();

    expect(find.textContaining('type: NeverRegistered'), findsOneWidget);
    expect(find.textContaining('tag: nope'), findsOneWidget);
    expect(find.textContaining('stack trace: yes'), findsOneWidget);
  });

  testWidgets('3. a second put keeps the first instance and warns',
      (tester) async {
    await openDemo(tester);

    await tester.tap(find.text('Put the same type twice'));
    await tester.pump();

    expect(find.textContaining('second put returned: first'), findsOneWidget);
    expect(find.textContaining('discarded instance initialized: false'),
        findsOneWidget);
    expect(find.textContaining('already registered'), findsOneWidget);
  });

  testWidgets('4. the lookup benchmark reports a per-call cost',
      (tester) async {
    await openDemo(tester);
    await scrollTo(tester, find.text('Time 100000 lookups'));

    await tester.tap(find.text('Time 100000 lookups'));
    await tester.pump();

    expect(find.textContaining('ns/call'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('5. update() skips id-ed builders, updateAll() reaches them',
      (tester) async {
    await openDemo(tester);
    await scrollTo(tester, find.text('updateAll()'));

    int buildsOf(String label) {
      final text = tester
          .widgetList<Text>(find.textContaining('$label — builds:'))
          .single
          .data!;
      return int.parse(
          RegExp(r'builds: (\d+)').firstMatch(text)!.group(1)!);
    }

    final plainBefore = buildsOf('no id');
    final aBefore = buildsOf("id 'a'");
    final bBefore = buildsOf("id 'b'");

    // update() reaches the id-less builder only.
    await tester.tap(find.text('update()'));
    await tester.pump();
    expect(buildsOf('no id'), plainBefore + 1);
    expect(buildsOf("id 'a'"), aBefore);
    expect(buildsOf("id 'b'"), bBefore);

    // update(['a']) reaches that one id only.
    await tester.tap(find.text("update(['a'])"));
    await tester.pump();
    expect(buildsOf('no id'), plainBefore + 1);
    expect(buildsOf("id 'a'"), aBefore + 1);
    expect(buildsOf("id 'b'"), bBefore);

    // updateAll() reaches all three.
    await tester.tap(find.text('updateAll()'));
    await tester.pump();
    expect(buildsOf('no id'), plainBefore + 2);
    expect(buildsOf("id 'a'"), aBefore + 2);
    expect(buildsOf("id 'b'"), bBefore + 1);
  });
}
