import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_demo/page_state_demo.dart';

void main() {
  tearDown(Get.reset);

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: PageStateDemoPage()));
    await tester.pump();
  }

  testWidgets('the page loads, then shows the articles', (tester) async {
    await open(tester);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Reactive Dart'), findsOneWidget);

    // The section is still loading on its own.
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Nice write-up'), findsOneWidget);
  });

  testWidgets('empty mode shows the empty view', (tester) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('empty'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('No articles yet'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('error mode shows the message and retry works', (tester) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('error'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('The server said no'), findsOneWidget);

    // Switch back to data and retry re-runs the last load.
    Get.find<ArticlesController>().mode = Mode.data;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Reactive Dart'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('paywall mode reaches the custom state', (tester) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('paywall'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('3 free articles left'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('refresh keeps the current list on screen', (tester) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Reactive Dart'), findsOneWidget);

    await tester.tap(find.text('refresh'));
    await tester.pump();
    // Mid-flight: the old data is still there, no spinner replaced it.
    expect(find.text('Reactive Dart'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Second item'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('reloading the section leaves the articles alone',
      (tester) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Reactive Dart'), findsOneWidget);

    await tester.tap(find.text('Reload section'));
    await tester.pump();

    // The article list survived the section's loading state.
    expect(find.text('Reactive Dart'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Bookmarked'), findsOneWidget);
  });
}
