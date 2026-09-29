import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class Articles extends GetxController with PageStateMixin<List<String>> {
  late final comments = section<List<String>>('comments');
}

final class Paywalled extends PageCustomState<List<String>> {
  const Paywalled(this.remaining);

  final int remaining;
}

/// Exhaustive over the six direct subtypes, so this compiling is itself the
/// guarantee that a missing branch would be a compile error.
String describe(PageState<List<String>> state) => switch (state) {
      Paywalled(:final remaining) => 'paywalled:$remaining',
      PageIdle() => 'idle',
      PageLoading() => 'loading',
      PageEmpty() => 'empty',
      PageFailure(:final error) => 'failure:$error',
      PageData(:final value) => 'data:${value.length}',
      PageCustomState() => 'custom',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  group('PageState', () {
    test('switch is exhaustive over every variant', () {
      expect(describe(const PageIdle()), 'idle');
      expect(describe(const PageLoading()), 'loading');
      expect(describe(const PageEmpty()), 'empty');
      expect(describe(const PageFailure('boom')), 'failure:boom');
      expect(describe(const PageData(['a', 'b'])), 'data:2');
      expect(describe(const Paywalled(3)), 'paywalled:3');
    });

    test('a custom state is matched by the broad branch when not listed', () {
      // A custom type the switch above does not name falls into
      // PageCustomState().
      expect(describe(const _OtherCustom()), 'custom');
    });

    test('the read helpers agree with the variants', () {
      const data = PageData<List<String>>(['a']);
      expect(data.isData, isTrue);
      expect(data.valueOrNull, ['a']);
      expect(data.errorOrNull, isNull);

      const failure = PageFailure<List<String>>('nope');
      expect(failure.isFailure, isTrue);
      expect(failure.errorOrNull, 'nope');
      expect(failure.valueOrNull, isNull);

      expect(const PageIdle<List<String>>().isIdle, isTrue);
      expect(const PageLoading<List<String>>().isLoading, isTrue);
      expect(const PageEmpty<List<String>>().isEmpty, isTrue);
      expect(const Paywalled(1).isCustom, isTrue);
    });
  });

  group('load', () {
    test('goes loading then data, notifying once per step', () {
      final controller = Articles();
      final seen = <String>[];
      controller.addListener(() => seen.add(describe(controller.state)));

      final done = controller.load(() async => ['a']);
      expect(seen, ['loading']);
      return done.then((_) {
        expect(seen, ['loading', 'data:1']);
        expect(controller.data, ['a']);
      });
    });

    test('an empty collection lands on PageEmpty', () async {
      final controller = Articles();
      await controller.load(() async => <String>[]);
      expect(controller.state, isA<PageEmpty<List<String>>>());
      expect(controller.data, isNull);
    });

    test('isEmpty can override what counts as empty', () async {
      final controller = Articles();
      await controller.load(() async => <String>[], isEmpty: (_) => false);
      expect(controller.state, isA<PageData<List<String>>>());
      expect(controller.data, isEmpty);
    });

    test('an async error lands on PageFailure with a stack trace', () async {
      final controller = Articles();
      await controller.load(() async => throw StateError('async'));
      final state = controller.state;
      expect(state, isA<PageFailure<List<String>>>());
      final failure = state as PageFailure<List<String>>;
      expect(failure.error, isA<StateError>());
      expect(failure.stackTrace, isNotNull);
    });

    test('a synchronous throw is caught too', () async {
      final controller = Articles();
      await controller.load(() => throw StateError('sync'));
      expect(controller.state, isA<PageFailure<List<String>>>());
    });

    test('only the newest load applies', () async {
      final controller = Articles();
      final first = Completer<List<String>>();
      final second = Completer<List<String>>();

      unawaited(controller.load(() => first.future));
      unawaited(controller.load(() => second.future));

      second.complete(['second']);
      await Future<void>.delayed(Duration.zero);
      first.complete(['first']);
      await Future<void>.delayed(Duration.zero);

      expect(controller.data, ['second']);
    });

    test('keepDataWhileLoading leaves the old data on screen', () async {
      final controller = Articles();
      await controller.load(() async => ['a']);

      final pending = Completer<List<String>>();
      final refreshing =
          controller.load(() => pending.future, keepDataWhileLoading: true);
      expect(controller.state, isA<PageData<List<String>>>());
      expect(controller.data, ['a']);

      pending.complete(['b']);
      await refreshing;
      expect(controller.data, ['b']);
    });

    test('without keepDataWhileLoading it shows loading again', () async {
      final controller = Articles();
      await controller.load(() async => ['a']);
      final pending = Completer<List<String>>();
      unawaited(controller.load(() => pending.future));
      expect(controller.state, isA<PageLoading<List<String>>>());
      pending.complete(['b']);
    });

    test('mapState can end a load in a custom state', () async {
      final controller = Articles();
      await controller.load(
        () async => ['a'],
        mapState: (value) => value.first == 'a' ? const Paywalled(3) : null,
      );
      expect(controller.state, isA<Paywalled>());
      expect((controller.state as Paywalled).remaining, 3);
    });

    test('mapState returning null falls back to the usual decision', () async {
      final controller = Articles();
      await controller.load(() async => ['a'], mapState: (_) => null);
      expect(controller.data, ['a']);

      await controller.load(() async => <String>[], mapState: (_) => null);
      expect(controller.state, isA<PageEmpty<List<String>>>());
    });

    test('retry replays mapState too', () async {
      final controller = Articles();
      await controller.load(
        () async => ['a'],
        mapState: (_) => const Paywalled(1),
      );
      controller.setIdle();
      await controller.retry();
      expect(controller.state, isA<Paywalled>());
    });

    test('retry runs the last body again', () async {
      final controller = Articles();
      var calls = 0;
      await controller.load(() async {
        calls++;
        if (calls == 1) throw StateError('first');
        return ['ok'];
      });
      expect(controller.state, isA<PageFailure<List<String>>>());

      await controller.retry();
      expect(calls, 2);
      expect(controller.data, ['ok']);
    });

    test('retry without a previous load does nothing', () async {
      final controller = Articles();
      await controller.retry();
      expect(controller.state, isA<PageIdle<List<String>>>());
    });

    test('reset goes back to idle and drops the in-flight load', () async {
      final controller = Articles();
      final pending = Completer<List<String>>();
      unawaited(controller.load(() => pending.future));
      controller.reset();
      expect(controller.state, isA<PageIdle<List<String>>>());

      pending.complete(['late']);
      await Future<void>.delayed(Duration.zero);
      expect(controller.state, isA<PageIdle<List<String>>>());
    });

    test('a result arriving after onClose is ignored', () async {
      final controller = Get.put(Articles());
      final pending = Completer<List<String>>();
      unawaited(controller.load(() => pending.future));

      Get.delete<Articles>();
      pending.complete(['late']);
      await Future<void>.delayed(Duration.zero);

      expect(controller.state, isA<PageLoading<List<String>>>());
      expect(controller.data, isNull);
    });
  });

  group('sections', () {
    test('the same id returns the same holder', () {
      final controller = Articles();
      expect(controller.section<List<String>>('comments'),
          same(controller.comments));
      expect(controller.hasSection('comments'), isTrue);
      expect(controller.hasSection('other'), isFalse);
    });

    test('a section is independent of the page state', () async {
      final controller = Articles();
      await controller.load(() async => ['article']);
      await controller.comments.load(() async => <String>[]);

      expect(controller.state, isA<PageData<List<String>>>());
      expect(controller.comments.state, isA<PageEmpty<List<String>>>());
    });

    test('a section notifies its id, the page notifies the id-less listeners',
        () {
      final controller = Articles();
      var plain = 0;
      var byId = 0;
      controller.addListener(() => plain++);
      controller.addListenerId('comments', () => byId++);

      controller.setLoading();
      expect(plain, 1);
      expect(byId, 0);

      controller.comments.setLoading();
      expect(plain, 1);
      expect(byId, 1);
    });

    test('onClose drops in-flight section loads', () async {
      final controller = Get.put(Articles());
      final pending = Completer<List<String>>();
      unawaited(controller.comments.load(() => pending.future));

      Get.delete<Articles>();
      pending.complete(['late']);
      await Future<void>.delayed(Duration.zero);

      expect(controller.comments.state, isA<PageLoading<List<String>>>());
    });
  });

  group('setters', () {
    test('each one produces its variant', () {
      final controller = Articles();
      controller.setLoading(progress: 0.5);
      expect((controller.state as PageLoading).progress, 0.5);

      controller.setEmpty(message: 'none');
      expect((controller.state as PageEmpty).message, 'none');

      controller.setData(['a']);
      expect(controller.data, ['a']);

      controller.setFailure('boom');
      expect(controller.state.errorOrNull, 'boom');

      controller.setCustom(const Paywalled(2));
      expect(controller.state, isA<Paywalled>());

      controller.setIdle();
      expect(controller.state.isIdle, isTrue);
    });

    test('setting state after close is a no-op', () {
      final controller = Get.put(Articles());
      Get.delete<Articles>();
      controller.setData(['a']);
      expect(controller.state.isIdle, isTrue);
    });
  });

  group('a controller that shadows refresh()', () {
    test('reports the loop instead of hanging', () {
      final controller = Looping();
      expect(
        () => controller.setLoading(),
        throwsA(isA<FlutterError>().having((e) => e.message, 'message',
            allOf(contains('refresh()'), contains('levels deep')))),
      );
    });

    test('an async shadow stops instead of looping forever', () async {
      final controller = LoopingAsync();
      // Without the depth guard this never returns.
      await runZonedGuarded(() async {
        controller.setLoading();
      }, (_, _) {});
      expect(controller.notifications, lessThan(30));
    });
  });

  group('isEmptyValue', () {
    test('covers null, collections and blank strings', () {
      expect(isEmptyValue(null), isTrue);
      expect(isEmptyValue(<int>[]), isTrue);
      expect(isEmptyValue(<String, int>{}), isTrue);
      expect(isEmptyValue('   '), isTrue);
      expect(isEmptyValue(<int>[1]), isFalse);
      expect(isEmptyValue('a'), isFalse);
      expect(isEmptyValue(0), isFalse);
    });
  });
}

final class _OtherCustom extends PageCustomState<List<String>> {
  const _OtherCustom();
}

/// Shadows `ListNotifier.refresh()`, which `update()` calls, so every state
/// change re-enters it. The trap the demo page fell into.
class Looping extends GetxController with PageStateMixin<List<String>> {
  @override
  void refresh() => setData(['loop']);
}

/// The same trap in the shape it usually takes: `void` is a top type, so a
/// `Future<void> refresh()` on the controller silently overrides the
/// notifier's. The error surfaces on the returned future rather than
/// synchronously, but the loop still has to stop.
class LoopingAsync extends GetxController with PageStateMixin<List<String>> {
  int notifications = 0;

  @override
  Future<void> refresh() async {
    notifications++;
    setData(['loop']);
  }
}
