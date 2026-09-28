import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:get/get_state_manager/src/simple/list_notifier.dart';

void main() {
  group('Rx collections', () {
    test('default constructors create modifiable collections', () {
      final list = RxList<int>()..add(1);
      final map = RxMap<String, int>()..['a'] = 1;
      final set = RxSet<int>()..add(1);
      final empty = RxList<int>.empty()..add(1);

      expect(list, [1]);
      expect(map, {'a': 1});
      expect(set, {1});
      expect(empty, [1]);
    });

    test('assignAll accepts a lazy view of itself', () {
      final list = [1, 2, 3, 4].obs;
      list.assignAll(list.where((e) => e.isEven));
      expect(list, [2, 4]);

      final set = {1, 2, 3, 4}.obs;
      set.assignAll(set.where((e) => e.isOdd));
      expect(set, {1, 3});
    });

    test('assign on a plain list replaces its content', () {
      final list = [1, 2, 3]..assign(9);
      expect(list, [9]);
    });

    test('RxMap.assignAll copies the entries and notifies once', () {
      final map = <String, int>{'a': 1}.obs;
      final source = {'b': 2};
      var calls = 0;
      map.addListener(() => calls++);

      map.assignAll(source);
      source['c'] = 3;

      expect(map, {'b': 2});
      expect(calls, 1);
    });

    test('RxMap [] with a key of another type returns null', () {
      final map = <String, int>{'a': 1}.obs;
      final Object key = 1;
      expect(map[key], isNull);
    });
  });

  group('Rx values', () {
    test('RxnDouble - subtracts', () {
      final value = RxnDouble(5.0);
      value - 2;
      expect(value.value, 3.0);
    });

    test('RxnBool ^ returns null for a null value', () {
      expect(RxnBool() ^ true, isNull);
      expect(RxnBool(true) ^ true, isFalse);
      expect(RxnBool(false) ^ true, isTrue);
    });

    test('trigger notifies listeners even on the first same value', () {
      final value = 2.obs;
      var calls = 0;
      value.addListener(() => calls++);

      value.trigger(2);
      value.trigger(2);

      expect(calls, 2);
    });

    test('setting the value does not subscribe the current observer', () {
      final value = 0.obs;
      Notifier.instance.append(
        TrackedBuild(updater: () {}, throwException: false),
        () => value.value = 1,
      );
      expect(value.listenersLength, 0);
    });

    test('stream can be listened to again after the last cancel', () async {
      final value = 0.obs;
      final first = <int>[];
      final second = <int>[];

      final sub = value.listen(first.add);
      value.value = 1;
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      value.listen(second.add);
      value.value = 2;
      await Future<void>.delayed(Duration.zero);

      expect(first, [1]);
      expect(second, [2]);
    });

    test('close is idempotent and ignores later writes', () {
      final value = 0.obs;
      value.close();
      value.close();
      value.value = 1;
      expect(value.isDisposed, isTrue);
    });

    test('bindStream subscriptions are cancelled on close', () async {
      final controller = StreamController<int>.broadcast();
      final value = 0.obs;
      value.bindStream(controller.stream);

      controller.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(value.value, 1);

      value.close();
      expect(controller.hasListener, isFalse);
      await controller.close();
    });

    test('removing a listener after close does not throw', () {
      final value = 0.obs;
      final dispose = value.addListener(() {});
      value.close();
      expect(dispose, returnsNormally);
      expect(() => value.removeListener(() {}), returnsNormally);
    });
  });

  group('Notifier', () {
    test('restores the tracking state when the builder throws', () {
      final value = 0.obs;
      expect(
        () => Notifier.instance.append(
          TrackedBuild(updater: () {}),
          () => throw StateError('boom'),
        ),
        throwsStateError,
      );

      // Reading outside of a builder must not subscribe anything.
      value.value;
      expect(value.listenersLength, 0);
    });

    test('a subscription is kept across builds of the same tracker', () {
      final value = 0.obs;
      final tracked = TrackedBuild(updater: () {});

      Notifier.instance.append(tracked, () => value.value);
      expect(value.listenersLength, 1);
      expect(tracked.subscriptionCount, 1);

      // Rebuilding no longer unsubscribes and resubscribes.
      Notifier.instance.append(tracked, () => value.value);
      expect(value.listenersLength, 1);
      expect(tracked.subscriptionCount, 1);

      tracked.dispose();
      expect(value.listenersLength, 0);
    });

    test('reading the same observable twice in one build subscribes once', () {
      final value = 0.obs;
      final tracked = TrackedBuild(updater: () {});
      final other = 0.obs;

      Notifier.instance.append(tracked, () {
        value.value;
        other.value;
        value.value; // interleaved, so the `_lastRead` shortcut does not apply
      });

      expect(value.listenersLength, 1);
      expect(other.listenersLength, 1);
      expect(tracked.subscriptionCount, 2);
      tracked.dispose();
    });

    test('an observable not read by the last build is unsubscribed', () {
      final a = 0.obs;
      final b = 0.obs;
      final tracked = TrackedBuild(updater: () {});

      Notifier.instance.append(tracked, () {
        a.value;
        b.value;
      });
      expect(tracked.subscriptionCount, 2);

      Notifier.instance.append(tracked, () => a.value);
      expect(a.listenersLength, 1);
      expect(b.listenersLength, 0);
      expect(tracked.subscriptionCount, 1);
      tracked.dispose();
    });

    test('a build that reads nothing keeps the previous subscriptions', () {
      final value = 0.obs;
      final tracked = TrackedBuild(updater: () {}, throwException: false);

      Notifier.instance.append(tracked, () => value.value);
      expect(value.listenersLength, 1);

      // Reads nothing: ObxError is off here, and the sweep drops the
      // subscription because it was not read.
      Notifier.instance.append(tracked, () => 0);
      expect(value.listenersLength, 0);
      tracked.dispose();
    });

    test('bindStream disposers only live for one build', () async {
      final source = StreamController<int>.broadcast();
      final value = 0.obs;
      final tracked = TrackedBuild(updater: () {});

      Notifier.instance.append(tracked, () {
        value.value;
        value.bindStream(source.stream);
      });
      expect(tracked.extraDisposers, hasLength(1));

      // The next build cancels the previous bindStream subscription.
      Notifier.instance.append(tracked, () => value.value);
      expect(tracked.extraDisposers, isEmpty);

      source.add(5);
      await Future<void>.delayed(Duration.zero);
      expect(value.value, 0, reason: 'the stream was unbound');

      tracked.dispose();
      await source.close();
    });

    test('throws the exported ObxError when nothing is observed', () {
      expect(
        () => Notifier.instance.append(
          TrackedBuild(updater: () {}),
          () => 0,
        ),
        throwsA(isA<ObxError>()),
      );
    });
  });

  group('Workers', () {
    test('debounce does not fire after dispose', () async {
      final value = 0.obs;
      var calls = 0;
      final worker = debounce(value, (_) => calls++,
          time: const Duration(milliseconds: 20));

      value.value = 1;
      await Future<void>.delayed(Duration.zero);
      worker.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(calls, 0);
    });

    test('interval does not fire after dispose', () async {
      final value = 0.obs;
      var calls = 0;
      final worker = interval(value, (_) => calls++,
          time: const Duration(milliseconds: 20));

      value.value = 1;
      await Future<void>.delayed(Duration.zero);
      worker.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(calls, 0);
    });

    test('interval fires once per window', () async {
      final value = 0.obs;
      final received = <int>[];
      interval(value, received.add, time: const Duration(milliseconds: 20));

      value.value = 1;
      value.value = 2;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(received, [1]);
    });
  });

  group('MiniStream', () {
    test('close twice is a no-op and cancelOnError removes listener', () {
      final stream = MiniStream<int>();
      final errors = <Object>[];
      stream.listen((_) {}, onError: errors.add, cancelOnError: true);

      stream.addError('e1');
      stream.addError('e2');
      expect(errors, ['e1']);
      expect(stream.length, 0);

      stream.close();
      expect(stream.close, returnsNormally);
    });
  });
}
