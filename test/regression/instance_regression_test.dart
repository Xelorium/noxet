import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class Counter extends GetxController {
  int inits = 0;
  int readies = 0;
  int closes = 0;

  @override
  void onInit() {
    super.onInit();
    inits++;
  }

  @override
  void onReady() {
    super.onReady();
    readies++;
  }

  @override
  void onClose() {
    closes++;
    super.onClose();
  }
}

class ReentrantController extends GetxController {
  int inits = 0;

  @override
  void onInit() {
    super.onInit();
    inits++;
    Get.find<ReentrantController>();
  }
}

class Foo {}

class FooBar {}

class Service extends GetxService {
  int closes = 0;

  @override
  void onClose() {
    closes++;
    super.onClose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(Get.reset);

  test('putOrFind starts a lazily registered instance', () {
    Get.lazyPut(() => Counter());
    final counter = Get.putOrFind(() => Counter());
    expect(counter.initialized, isTrue);
    expect(counter.inits, 1);
    expect(Get.find<Counter>().inits, 1);
  });

  test('find from inside onInit does not run onInit twice', () {
    Get.lazyPut(() => ReentrantController());
    expect(Get.find<ReentrantController>().inits, 1);
  });

  test('type + tag does not collide with another type', () {
    final foo = Foo();
    final fooBar = FooBar();
    Get.put(foo, tag: 'Bar');
    Get.put(fooBar);

    expect(Get.find<Foo>(tag: 'Bar'), same(foo));
    expect(Get.find<FooBar>(), same(fooBar));
  });

  test('reloadAll closes the instances', () {
    final counter = Get.put(Counter());
    Get.reloadAll();
    expect(counter.closes, 1);
  });

  test('reset closes instances, including services', () {
    final counter = Get.put(Counter());
    final service = Get.put(Service());
    Get.reset();
    expect(counter.closes, 1);
    expect(service.closes, 1);
    expect(Get.isRegistered<Counter>(), isFalse);
  });

  test('a dirty registration is replaced and its instance closed', () {
    final first = Get.put(Counter());
    Get.markAsDirty<Counter>();
    final second = Get.put(Counter());

    expect(second, isNot(same(first)));
    expect(first.closes, 1);
    expect(Get.find<Counter>(), same(second));

    expect(Get.delete<Counter>(), isTrue);
    expect(second.closes, 1);
    expect(Get.isRegistered<Counter>(), isFalse);
  });

  testWidgets('onReady is not called when closed before the first frame',
      (tester) async {
    final counter = Get.put(Counter());
    Get.delete<Counter>();
    await tester.pump();
    expect(counter.readies, 0);
  });

  test('isPrepared and getInstanceInfo on a missing type', () {
    expect(Get.isPrepared<Counter>(), isFalse);
    expect(Get.getInstanceInfo<Counter>().isRegistered, isFalse);
  });

  test('StateMixin futurize applies only the latest result', () async {
    final controller = _Loader();
    final first = Completer<String>();
    final second = Completer<String>();
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.futurize(() => first.future);
    controller.futurize(() => second.future);
    second.complete('second');
    await Future<void>.delayed(Duration.zero);
    first.complete('first');
    await Future<void>.delayed(Duration.zero);

    expect(controller.state, 'second');
    expect(controller.status.isSuccess, isTrue);
    // loading + success, without the duplicated refresh.
    expect(notifications, 2);
  });

  test('StateMixin futurize catches synchronous errors', () async {
    final controller = _Loader();
    controller.futurize(() => throw StateError('sync'));
    await Future<void>.delayed(Duration.zero);
    expect(controller.status.isError, isTrue);
  });

  group('find throws a typed error', () {
    test('without a tag', () {
      expect(
        () => Get.find<Counter>(),
        throwsA(isA<GetInstanceNotFoundError>()
            .having((e) => e.type, 'type', Counter)
            .having((e) => e.tag, 'tag', isNull)),
      );
    });

    test('with a tag', () {
      expect(
        () => Get.find<Counter>(tag: 'missing'),
        throwsA(isA<GetInstanceNotFoundError>()
            .having((e) => e.type, 'type', Counter)
            .having((e) => e.tag, 'tag', 'missing')),
      );
    });

    test('is an Error, so it carries a stack trace', () {
      Object? thrown;
      StackTrace? stack;
      try {
        Get.find<Counter>();
      } catch (e, s) {
        thrown = e;
        stack = s;
      }
      expect(thrown, isA<Error>());
      expect(thrown, isNot(isA<String>()));
      expect(stack, isNotNull);
      expect(thrown.toString(), contains('Counter'));
      expect(thrown.toString(), contains('Get.put'));
    });

    test('a registered instance with the same tag is unaffected', () {
      final counter = Get.put(Counter(), tag: 'a');
      expect(Get.find<Counter>(tag: 'a'), same(counter));
      expect(() => Get.find<Counter>(tag: 'b'),
          throwsA(isA<GetInstanceNotFoundError>()));
      expect(() => Get.find<Counter>(),
          throwsA(isA<GetInstanceNotFoundError>()));
    });
  });

  group('a second put of the same type', () {
    late LogWriterCallback previousLog;
    late List<String> errors;

    setUp(() {
      errors = <String>[];
      previousLog = Get.log;
      Get.log = (String text, {bool isError = false}) {
        if (isError) errors.add(text);
      };
    });

    tearDown(() => Get.log = previousLog);

    test('warns and keeps the first instance', () {
      final first = Get.put(Counter());
      final second = Counter();
      final returned = Get.put(second);

      expect(returned, same(first));
      expect(Get.find<Counter>(), same(first));
      // The discarded instance was never initialized nor closed.
      expect(second.initialized, isFalse);
      expect(second.closes, 0);
      expect(errors, hasLength(1));
      expect(errors.single, contains('Counter'));
      expect(errors.single, contains('already registered'));
    });

    test('warns per tag, not per type', () {
      Get.put(Counter(), tag: 'a');
      Get.put(Counter(), tag: 'b');
      expect(errors, isEmpty);

      Get.put(Counter(), tag: 'a');
      expect(errors, hasLength(1));
      expect(errors.single, contains('Counter#a'));
    });

    test('does not warn after a delete or markAsDirty', () {
      Get.put(Counter());
      Get.delete<Counter>();
      Get.put(Counter());
      Get.markAsDirty<Counter>();
      Get.put(Counter());
      expect(errors, isEmpty);
    });

    test('lazyPut stays a silent no-op', () {
      Get.lazyPut(() => Counter());
      Get.lazyPut(() => Counter());
      expect(errors, isEmpty);
    });
  });

  group('registration keys', () {
    test('the "Type#tag" string key still works with delete(key:)', () {
      final counter = Get.put(Counter(), tag: 'a');
      expect(Get.delete<Counter>(key: 'Counter#a'), isTrue);
      expect(counter.closes, 1);
      expect(Get.isRegistered<Counter>(tag: 'a'), isFalse);
    });

    test('the "Type" string key still works with reload(key:)', () {
      Get.lazyPut(() => Counter());
      final counter = Get.find<Counter>();
      Get.reload<Counter>(key: 'Counter');
      expect(counter.closes, 1);
      expect(Get.find<Counter>(), isNot(same(counter)));
    });

    test('markAsDirty(key:) still works', () {
      final first = Get.put(Counter(), tag: 'a');
      Get.markAsDirty<Counter>(key: 'Counter#a');
      final second = Get.put(Counter(), tag: 'a');
      expect(second, isNot(same(first)));
      expect(first.closes, 1);
    });

    test('an unknown string key is reported, not thrown', () {
      expect(Get.delete<Counter>(key: 'Nope#nope'), isFalse);
      Get.reload<Counter>(key: 'Nope#nope');
    });

    test('deleteAll closes every registration, tagged or not', () {
      final plain = Get.put(Counter());
      final tagged = Get.put(Counter(), tag: 'a');
      Get.deleteAll();
      expect(plain.closes, 1);
      expect(tagged.closes, 1);
      expect(Get.isRegistered<Counter>(), isFalse);
      expect(Get.isRegistered<Counter>(tag: 'a'), isFalse);
    });

    test('reloadAll restarts every registration, tagged or not', () {
      Get.lazyPut(() => Counter());
      Get.lazyPut(() => Counter(), tag: 'a');
      final plain = Get.find<Counter>();
      final tagged = Get.find<Counter>(tag: 'a');
      Get.reloadAll();
      expect(plain.closes, 1);
      expect(tagged.closes, 1);
      expect(Get.find<Counter>(), isNot(same(plain)));
      expect(Get.find<Counter>(tag: 'a'), isNot(same(tagged)));
    });

    test('getInstanceInfo and isPrepared agree per tag', () {
      Get.lazyPut(() => Counter(), tag: 'a');
      expect(Get.isPrepared<Counter>(tag: 'a'), isTrue);
      expect(Get.isPrepared<Counter>(), isFalse);
      expect(Get.getInstanceInfo<Counter>(tag: 'a').isRegistered, isTrue);
      expect(Get.getInstanceInfo<Counter>().isRegistered, isFalse);

      Get.find<Counter>(tag: 'a');
      expect(Get.isPrepared<Counter>(tag: 'a'), isFalse);
    });
  });
}

class _Loader extends GetxController with StateMixin<String> {}
