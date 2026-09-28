// Cost of a tracked (Obx/GetX) build and of subscribing while notifying.
// Uses only APIs that predate the tracking rework, so the same file can be run
// against an older checkout to produce the "before" column.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get/get_state_manager/src/simple/list_notifier.dart';

void printValue(String value) {
  // ignore: avoid_print
  print(value);
}

int measure(String name, int ops, void Function() body) {
  // Warm up so the JIT does not dominate, then keep the best of 5 runs.
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
  final perOp = (best * 1000 / ops).toStringAsFixed(0);
  printValue('[$name] ${best}us ($perOp ns/op)');
  return best;
}

class Counter extends GetxController {
  int value = 0;
}

const builds = 100000;

void main() {
  tearDown(Get.reset);

  /// Repeatedly rebuilds one tracked builder, the way an `Obx` element does:
  /// the tracking state (`data` and `disposers`) belongs to the element and
  /// lives across builds, and each build drops the one-shot disposers first.
  ///
  /// On the pre-rework tree the per-build subscriptions lived in [disposers],
  /// so clearing it here is what `Obx.build` did; on the current tree they
  /// live inside the object and `append` sweeps them. The same harness
  /// therefore measures what each tree's `Obx` really does.
  void rebuild(String name, void Function() read) {
    final disposers = <Disposer>[];
    void updater() {}
    final data = NotifyData(updater: updater, disposers: disposers);

    measure(name, builds, () {
      for (var i = 0; i < builds; i++) {
        for (final disposer in disposers) {
          disposer();
        }
        disposers.clear();
        Notifier.instance.append(data, read);
      }
    });
    // Release whatever the last build left subscribed (on the pre-rework tree
    // these are the per-build subscriptions themselves).
    for (final disposer in disposers) {
      disposer();
    }
    disposers.clear();
  }

  test('tracked build reading N observables', () {
    for (final count in [1, 5, 20]) {
      final values = [for (var i = 0; i < count; i++) i.obs];
      rebuild('tracked build reading $count observables', () {
        for (final value in values) {
          value.value;
        }
      });
    }
  });

  test('tracked build re-reading the same observable in a loop', () {
    final list = List<int>.generate(50, (i) => i).obs;
    rebuild('tracked build reading a 50 item RxList', () {
      var sum = 0;
      for (var i = 0; i < list.length; i++) {
        sum += list[i];
      }
      if (sum < 0) printValue('never');
    });
  });

  // Each case repeats the interleave enough times to stay well above the
  // stopwatch's resolution; per-op is per subscribe/unsubscribe + notify pair.
  const repeats = {10: 2000, 100: 200, 500: 20};

  test('subscribe while notifying', () {
    for (final n in [10, 100, 500]) {
      final times = repeats[n]!;
      measure('subscribe + notify interleaved up to $n listeners', n * times,
          () {
        for (var r = 0; r < times; r++) {
          final controller = Counter();
          for (var i = 0; i < n; i++) {
            controller.addListener(() {});
            controller.update();
          }
          controller.dispose();
        }
      });
    }
  });

  test('unsubscribe while notifying', () {
    for (final n in [10, 100, 500]) {
      final times = repeats[n]!;
      measure('unsubscribe + notify interleaved from $n listeners', n * times,
          () {
        for (var r = 0; r < times; r++) {
          final controller = Counter();
          final disposers = <Disposer>[
            for (var i = 0; i < n; i++) controller.addListener(() {}),
          ];
          for (final disposer in disposers) {
            disposer();
            controller.update();
          }
          controller.dispose();
        }
      });
    }
  });

  testWidgets('GetBuilder mount', (tester) async {
    Get.put(Counter());
    Widget tree(int count) => Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              for (var i = 0; i < count; i++)
                GetBuilder<Counter>(
                  autoRemove: false,
                  builder: (_) => const SizedBox(height: 1),
                ),
            ],
          ),
        );

    // Noisy: dominated by Flutter's own mount pipeline. Kept for reference.
    final watch = Stopwatch()..start();
    for (var i = 0; i < 50; i++) {
      await tester.pumpWidget(tree(100));
      await tester.pumpWidget(const SizedBox());
    }
    watch.stop();
    printValue('[mount 100 GetBuilders x50 (noisy)] '
        '${watch.elapsedMicroseconds}us');
  });
}
