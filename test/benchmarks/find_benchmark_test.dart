import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void printValue(String value) {
  // ignore: avoid_print
  print(value);
}

int measure(String name, void Function() body) {
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
  printValue('[$name] ${best}us');
  return best;
}

class Controller extends GetxController {
  int count = 0;
}

class CounterView extends GetView<Controller> {
  const CounterView({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

const iterations = 100000;

void main() {
  tearDown(Get.reset);

  test('Get.find without tag', () {
    Get.put(Controller());
    measure('Get.find x $iterations', () {
      for (var i = 0; i < iterations; i++) {
        Get.find<Controller>();
      }
    });
  });

  test('Get.find with tag', () {
    Get.put(Controller(), tag: 'tagged');
    measure('Get.find(tag:) x $iterations', () {
      for (var i = 0; i < iterations; i++) {
        Get.find<Controller>(tag: 'tagged');
      }
    });
  });

  test('GetView.controller', () {
    Get.put(Controller());
    const view = CounterView();
    measure('GetView.controller x $iterations', () {
      for (var i = 0; i < iterations; i++) {
        view.controller;
      }
    });
  });

  test('Get.isRegistered', () {
    Get.put(Controller());
    measure('Get.isRegistered x $iterations', () {
      for (var i = 0; i < iterations; i++) {
        Get.isRegistered<Controller>();
      }
    });
  });

  test('Get.find with 50 other registrations', () {
    for (var i = 0; i < 50; i++) {
      Get.put(Controller(), tag: 'other$i');
    }
    Get.put(Controller());
    measure('Get.find among 51 registrations x $iterations', () {
      for (var i = 0; i < iterations; i++) {
        Get.find<Controller>();
      }
    });
  });
}
