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
}

class _Loader extends GetxController with StateMixin<String> {}
