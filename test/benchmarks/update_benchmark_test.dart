// End to end cost of `GetxController.update()` and of mounting `GetBuilder`s,
// measured through the real widget pipeline. Only uses APIs that existed
// before the performance work, so the same file can be run against an older
// checkout to produce the "before" column.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void printValue(String value) {
  // ignore: avoid_print
  print(value);
}

/// Best of 5 runs, after one warm-up run.
Future<int> measureAsync(String name, Future<void> Function() body) async {
  await body();
  var best = -1;
  for (var run = 0; run < 5; run++) {
    final watch = Stopwatch()..start();
    await body();
    watch.stop();
    if (best < 0 || watch.elapsedMicroseconds < best) {
      best = watch.elapsedMicroseconds;
    }
  }
  printValue('[$name] ${best}us');
  return best;
}

int measure(String name, void Function() body) {
  body();
  var best = -1;
  for (var run = 0; run < 5; run++) {
    final watch = Stopwatch()..start();
    body();
    watch.stop();
    if (best < 0 || watch.elapsedMicroseconds < best) {
      best = watch.elapsedMicroseconds;
    }
  }
  printValue('[$name] ${best}us');
  return best;
}

class Counter extends GetxController {
  int value = 0;

  void bump() {
    value++;
    update();
  }

  void bumpId(Object id) {
    value++;
    update([id]);
  }
}

Widget wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: child,
    );

void main() {
  tearDown(Get.reset);

  // --- update() at the notifier level: the notify itself, no widgets. ---
  test('update() with N listeners', () {
    for (final listeners in [1, 100, 1000]) {
      final controller = Get.put(Counter(), tag: 'l$listeners');
      for (var i = 0; i < listeners; i++) {
        controller.addListener(() {});
      }
      measure('update() notify $listeners listeners x 10000', () {
        for (var i = 0; i < 10000; i++) {
          controller.update();
        }
      });
    }
  });

  test('update([id]) with N ids registered', () {
    final controller = Get.put(Counter());
    for (var i = 0; i < 1000; i++) {
      controller.addListenerId('id$i', () {});
    }
    measure('update([id]) among 1000 ids x 10000', () {
      for (var i = 0; i < 10000; i++) {
        controller.update(['id500']);
      }
    });
  });

  // --- update() end to end: notify + rebuild of mounted GetBuilders. ---
  testWidgets('update() rebuilding N GetBuilders', (tester) async {
    for (final builders in [1, 20, 100]) {
      Get.reset();
      final controller = Get.put(Counter());
      await tester.pumpWidget(wrap(Column(
        children: [
          for (var i = 0; i < builders; i++)
            GetBuilder<Counter>(
              autoRemove: false,
              builder: (c) => SizedBox(height: 1, width: c.value % 2 + 1),
            ),
        ],
      )));

      await measureAsync('update() -> rebuild $builders GetBuilders x 200',
          () async {
        for (var i = 0; i < 200; i++) {
          controller.update();
          await tester.pump();
        }
      });
      await tester.pumpWidget(const SizedBox());
    }
  });

  // The package's own share of an update(): iterate the listeners and mark the
  // GetBuilder elements dirty, without letting Flutter rebuild them. The end
  // to end numbers above are dominated by build/layout/paint, which hides it.
  testWidgets('update() notifying N mounted GetBuilders, no rebuild',
      (tester) async {
    for (final builders in [1, 20, 100]) {
      Get.reset();
      final controller = Get.put(Counter());
      await tester.pumpWidget(wrap(Column(
        children: [
          for (var i = 0; i < builders; i++)
            GetBuilder<Counter>(
              autoRemove: false,
              builder: (c) => const SizedBox(height: 1),
            ),
        ],
      )));

      measure('update() notify $builders mounted GetBuilders x 10000', () {
        for (var i = 0; i < 10000; i++) {
          controller.update();
        }
      });
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('update([id]) rebuilding 1 of N id-ed GetBuilders',
      (tester) async {
    Get.reset();
    final controller = Get.put(Counter());
    await tester.pumpWidget(wrap(Column(
      children: [
        for (var i = 0; i < 100; i++)
          GetBuilder<Counter>(
            id: 'id$i',
            autoRemove: false,
            builder: (c) => SizedBox(height: 1, width: c.value % 2 + 1),
          ),
      ],
    )));

    await measureAsync('update([id]) -> rebuild 1 of 100 GetBuilders x 200',
        () async {
      for (var i = 0; i < 200; i++) {
        controller.update(['id50']);
        await tester.pump();
      }
    });
  });

  // --- GetBuilder mount / unmount churn: Get.find + subscribe + dispose. ---
  testWidgets('mount and unmount N GetBuilders', (tester) async {
    Get.reset();
    Get.put(Counter());

    Widget tree(int builders) => wrap(Column(
          children: [
            for (var i = 0; i < builders; i++)
              GetBuilder<Counter>(
                autoRemove: false,
                builder: (c) => const SizedBox(height: 1),
              ),
          ],
        ));

    for (final builders in [1, 100]) {
      await measureAsync('mount + unmount $builders GetBuilders x 50',
          () async {
        for (var i = 0; i < 50; i++) {
          await tester.pumpWidget(tree(builders));
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  });

  testWidgets('mount and unmount 100 id-ed GetBuilders', (tester) async {
    Get.reset();
    Get.put(Counter());

    Widget tree() => wrap(Column(
          children: [
            for (var i = 0; i < 100; i++)
              GetBuilder<Counter>(
                id: 'id$i',
                autoRemove: false,
                builder: (c) => const SizedBox(height: 1),
              ),
          ],
        ));

    await measureAsync('mount + unmount 100 id-ed GetBuilders x 50', () async {
      for (var i = 0; i < 50; i++) {
        await tester.pumpWidget(tree());
        await tester.pumpWidget(const SizedBox());
      }
    });
  });
}
