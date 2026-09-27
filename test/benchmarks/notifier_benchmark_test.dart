import 'package:flutter_test/flutter_test.dart';
import 'package:get/state_manager.dart';
import 'package:get/get_state_manager/src/simple/list_notifier.dart';

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

void main() {
  test('notify N listeners', () {
    for (final listeners in [1, 100, 1000]) {
      final value = 0.obs;
      for (var i = 0; i < listeners; i++) {
        value.addListener(() {});
      }
      measure('notify $listeners listeners x 10000', () {
        for (var i = 0; i < 10000; i++) {
          value.value++;
        }
      });
    }
  });

  test('add and remove listeners', () {
    final value = 0.obs;
    final disposers = <Disposer>[
      for (var i = 0; i < 1000; i++) value.addListener(() {}),
    ];
    measure('remove + add 1000 of 1000 listeners', () {
      for (var i = 0; i < disposers.length; i++) {
        disposers[i]();
        disposers[i] = value.addListener(() {});
      }
    });
  });

  test('read a 1000 item RxList inside a tracked builder', () {
    final list = List<int>.generate(1000, (i) => i).obs;
    // Other observers already subscribed to the list.
    for (var i = 0; i < 100; i++) {
      list.addListener(() {});
    }
    measure('tracked read 1000 items, 100 listeners', () {
      final disposers = <Disposer>[];
      Notifier.instance.append(
        NotifyData(updater: () {}, disposers: disposers),
        () {
          var sum = 0;
          for (var i = 0; i < list.length; i++) {
            sum += list[i];
          }
          return sum;
        },
      );
      for (final dispose in disposers) {
        dispose();
      }
    });
  });

  test('RxList bulk operations notify once', () {
    final list = List<int>.generate(1000, (i) => i).obs;
    var calls = 0;
    list.addListener(() => calls++);

    void expectOne(String name, void Function() op) {
      calls = 0;
      op();
      expect(calls, 1, reason: name);
    }

    expectOne('insert', () => list.insert(0, -1));
    expectOne('removeAt', () => list.removeAt(0));
    expectOne('removeLast', () => list.removeLast());
    expectOne('removeRange', () => list.removeRange(0, 10));
    expectOne('setRange', () => list.setRange(0, 3, [7, 8, 9]));
    expectOne('setAll', () => list.setAll(0, [1, 2]));
    expectOne('fillRange', () => list.fillRange(0, 5, 0));
    expectOne('replaceRange', () => list.replaceRange(0, 5, [1]));
    expectOne('shuffle', () => list.shuffle());
    expectOne('clear', () => list.clear());

    measure('RxList.removeAt(0) x 250 on 1000 items, 10 listeners', () {
      final big = List<int>.generate(1000, (i) => i).obs;
      for (var i = 0; i < 10; i++) {
        big.addListener(() {});
      }
      for (var i = 0; i < 250; i++) {
        big.removeAt(0);
      }
    });
  });

  test('RxMap bulk operations notify once', () {
    final map = <int, int>{for (var i = 0; i < 100; i++) i: i}.obs;
    var calls = 0;
    map.addListener(() => calls++);

    void expectCalls(String name, int expected, void Function() op) {
      calls = 0;
      op();
      expect(calls, expected, reason: name);
    }

    expectCalls('addAll', 1, () => map.addAll({1000: 0, 1001: 1}));
    expectCalls(
      'addEntries',
      1,
      () => map.addEntries([const MapEntry(2000, 0)]),
    );
    expectCalls('updateAll', 1, () => map.updateAll((k, v) => v + 1));
    expectCalls('removeWhere', 1, () => map.removeWhere((k, v) => k > 999));
    expectCalls('putIfAbsent existing', 0, () => map.putIfAbsent(1, () => 0));
    expectCalls('putIfAbsent new', 1, () => map.putIfAbsent(5000, () => 0));
    expectCalls('update', 1, () => map.update(1, (v) => v + 1));
  });
}
