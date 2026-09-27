import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get_demo/main.dart';

void main() {
  tearDown(Get.reset);

  testWidgets('counter, todos and quote update the UI', (tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Count: 0'), findsOneWidget);
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(find.text('Count: 1'), findsOneWidget);

    await tester.tap(find.text('Add todo'));
    await tester.pump();
    expect(find.text('Todo 1'), findsOneWidget);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Keep it simple.'), findsOneWidget);
  });
}
