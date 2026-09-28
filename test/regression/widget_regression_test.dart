import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class Counter extends GetxController {
  final count = 0.obs;
  int closes = 0;

  @override
  void onClose() {
    closes++;
    super.onClose();
  }
}

class Numbers extends GetxController {
  int value = 0;

  void bump() {
    value++;
    update();
  }

  void bumpOne(Object id) {
    value++;
    update([id]);
  }

  void bumpAll() {
    value++;
    updateAll();
  }
}

class Item extends GetxController {
  int closes = 0;

  @override
  void onClose() {
    closes++;
    super.onClose();
  }
}

class Label extends GetWidget<Item> {
  const Label(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, textDirection: TextDirection.ltr);
}

void main() {
  tearDown(Get.reset);

  testWidgets('Bind.builder uses init', (tester) async {
    await tester.pumpWidget(
      Binds(
        binds: [Bind<Counter>.builder(init: () => Counter())],
        child: Builder(
          builder: (context) => Text('${context.get<Counter>().count.value}',
              textDirection: TextDirection.ltr),
        ),
      ),
    );
    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('non permanent Bind.put is removed on unmount', (tester) async {
    await tester.pumpWidget(Binds(
      binds: [Bind.put(Counter())],
      child: const SizedBox(),
    ));
    expect(Get.isRegistered<Counter>(), isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(Get.isRegistered<Counter>(), isFalse);
  });

  testWidgets('permanent Bind.put is kept on unmount', (tester) async {
    await tester.pumpWidget(Binds(
      binds: [Bind.put(Counter(), permanent: true)],
      child: const SizedBox(),
    ));
    await tester.pumpWidget(const SizedBox());
    expect(Get.isRegistered<Counter>(), isTrue);
  });

  testWidgets('Bind.spawn gives each Bind its own instance', (tester) async {
    Counter? a;
    Counter? b;
    await tester.pumpWidget(Column(children: [
      Binds(
        binds: [Bind.spawn(() => Counter())],
        child: Builder(builder: (context) {
          a = context.get<Counter>();
          return const SizedBox();
        }),
      ),
      Binds(
        binds: [Bind.spawn(() => Counter())],
        child: Builder(builder: (context) {
          b = context.get<Counter>();
          return const SizedBox();
        }),
      ),
    ]));
    expect(a, isNotNull);
    expect(a, isNot(same(b)));

    await tester.pumpWidget(const SizedBox());
    expect(a!.closes, 1);
    expect(b!.closes, 1);
  });

  testWidgets('trigger with the same value rebuilds Obx', (tester) async {
    final value = 1.obs;
    var builds = 0;
    await tester.pumpWidget(Obx(() {
      builds++;
      return Text('${value.value}', textDirection: TextDirection.ltr);
    }));
    value.trigger(1);
    await tester.pump();
    expect(builds, 2);
  });

  testWidgets('Obx releases every subscription on unmount', (tester) async {
    final a = 0.obs;
    final b = 0.obs;

    await tester.pumpWidget(Obx(
      () => Text('${a.value}/${b.value}', textDirection: TextDirection.ltr),
    ));
    expect(a.listenersLength, 1);
    expect(b.listenersLength, 1);

    // Subscriptions now outlive a rebuild, so unmount has to clear them.
    a.value = 1;
    await tester.pump();
    expect(a.listenersLength, 1);
    expect(b.listenersLength, 1);

    await tester.pumpWidget(const SizedBox());
    expect(a.listenersLength, 0);
    expect(b.listenersLength, 0);
  });

  testWidgets('Obx keeps rebuilding on every observable it reads',
      (tester) async {
    final a = 0.obs;
    final b = 0.obs;
    var builds = 0;

    await tester.pumpWidget(Obx(() {
      builds++;
      return Text('${a.value}/${b.value}', textDirection: TextDirection.ltr);
    }));
    expect(builds, 1);

    // Several rebuilds in a row: the sweep must not drop either subscription.
    for (var i = 1; i <= 3; i++) {
      a.value = i;
      await tester.pump();
      expect(builds, i + 1);
    }
    b.value = 1;
    await tester.pump();
    expect(builds, 5);
    expect(find.text('3/1'), findsOneWidget);
  });

  testWidgets('GetX releases its subscriptions on unmount', (tester) async {
    final counter = Get.put(Counter());

    await tester.pumpWidget(GetX<Counter>(
      builder: (c) =>
          Text('${c.count.value}', textDirection: TextDirection.ltr),
    ));
    expect(counter.count.listenersLength, 1);

    counter.count.value = 1;
    await tester.pump();
    expect(counter.count.listenersLength, 1);

    await tester.pumpWidget(const SizedBox());
    expect(counter.count.listenersLength, 0);
  });

  testWidgets('GetX drops subscriptions that are no longer read',
      (tester) async {
    final useB = true.obs;
    final b = 0.obs;
    Get.put(Counter());
    var builds = 0;

    await tester.pumpWidget(GetX<Counter>(
      builder: (_) {
        builds++;
        return Text(useB.value ? '${b.value}' : 'off',
            textDirection: TextDirection.ltr);
      },
    ));
    expect(b.listenersLength, 1);

    useB.value = false;
    await tester.pump();
    expect(builds, 2);
    expect(b.listenersLength, 0);

    b.value = 1;
    await tester.pump();
    expect(builds, 2);
  });

  testWidgets('Obx drops subscriptions that are no longer read',
      (tester) async {
    final useB = true.obs;
    final b = 0.obs;
    var builds = 0;
    await tester.pumpWidget(Obx(() {
      builds++;
      final text = useB.value ? '${b.value}' : 'off';
      return Text(text, textDirection: TextDirection.ltr);
    }));

    useB.value = false;
    await tester.pump();
    expect(builds, 2);

    b.value = 1;
    await tester.pump();
    expect(builds, 2);
  });

  testWidgets('closing an Rx before Obx unmounts does not throw',
      (tester) async {
    final value = 0.obs;
    await tester.pumpWidget(
        Obx(() => Text('${value.value}', textDirection: TextDirection.ltr)));
    value.close();
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('Obx can be updated while another widget is building',
      (tester) async {
    final value = 0.obs;
    await tester.pumpWidget(Column(children: [
      Obx(() => Text('${value.value}', textDirection: TextDirection.ltr)),
      Builder(builder: (context) {
        if (value.value == 0) value.value = 1;
        return const SizedBox();
      }),
    ]));
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('GetX can be updated while another widget is building',
      (tester) async {
    final controller = Get.put(Counter());
    await tester.pumpWidget(Column(children: [
      GetX<Counter>(
        builder: (c) =>
            Text('${c.count.value}', textDirection: TextDirection.ltr),
      ),
      Builder(builder: (context) {
        if (controller.count.value == 0) controller.count.value = 1;
        return const SizedBox();
      }),
    ]));
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('local GetX closes its controller and keeps the global one',
      (tester) async {
    final global = Get.put(Counter());
    final local = Counter();
    await tester.pumpWidget(GetX<Counter>(
      global: false,
      init: local,
      builder: (c) => Text('${c.count.value}', textDirection: TextDirection.ltr),
    ));
    await tester.pumpWidget(const SizedBox());

    expect(local.closes, 1);
    expect(global.closes, 0);
    expect(Get.isRegistered<Counter>(), isTrue);
  });

  testWidgets('GetBuilder follows a changed id', (tester) async {
    final controller = Get.put(Counter());
    var builds = 0;
    Widget build(Object id) => GetBuilder<Counter>(
          id: id,
          builder: (_) {
            builds++;
            return const SizedBox();
          },
        );

    await tester.pumpWidget(build('a'));
    await tester.pumpWidget(build('b'));
    final before = builds;

    controller.update(['b']);
    await tester.pump();
    expect(builds, before + 1);

    controller.update(['a']);
    await tester.pump();
    expect(builds, before + 1);
  });

  testWidgets('GetWidget uses the latest widget and keeps its controller',
      (tester) async {
    Get.spawn(() => Item());
    await tester.pumpWidget(const Label('first'));
    final element = tester.element(find.byType(Label));
    final controller = (element.widget as Label).controller;

    await tester.pumpWidget(const Label('second'));
    expect(find.text('second'), findsOneWidget);
    expect((tester.widget(find.byType(Label)) as Label).controller,
        same(controller));
    expect(Get.isRegistered<Item?>(), isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.closes, 1);
  });

  testWidgets('update() during build is deferred instead of throwing',
      (tester) async {
    final controller = Get.put(Numbers());
    var builds = 0;

    await tester.pumpWidget(GetBuilder<Numbers>(
      builder: (c) {
        builds++;
        // A build that updates the controller it is reading, e.g. a lazily
        // initialized field. Marking the element dirty here used to throw
        // "setState() or markNeedsBuild() called during build".
        if (c.value == 0) c.bump();
        return Text('${c.value}', textDirection: TextDirection.ltr);
      },
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(controller.value, 1);
    expect(builds, 2);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('repeated update() before a frame rebuilds once', (tester) async {
    final controller = Get.put(Numbers());
    var builds = 0;

    await tester.pumpWidget(GetBuilder<Numbers>(
      builder: (c) {
        builds++;
        return Text('${c.value}', textDirection: TextDirection.ltr);
      },
    ));
    expect(builds, 1);

    for (var i = 0; i < 5; i++) {
      controller.bump();
    }
    await tester.pump();

    // One rebuild, showing the latest value: the element is already marked
    // for the next frame, so the following updates do no extra work.
    expect(builds, 2);
    expect(find.text('5'), findsOneWidget);

    // The guard is released by the rebuild, so the next update still lands.
    controller.bump();
    await tester.pump();
    expect(builds, 3);
    expect(find.text('6'), findsOneWidget);
  });

  testWidgets('repeated update([id]) before a frame rebuilds once',
      (tester) async {
    final controller = Get.put(Numbers());
    var builds = 0;

    await tester.pumpWidget(GetBuilder<Numbers>(
      id: 'a',
      builder: (c) {
        builds++;
        return Text('${c.value}', textDirection: TextDirection.ltr);
      },
    ));

    for (var i = 0; i < 5; i++) {
      controller.bumpOne('a');
    }
    await tester.pump();
    expect(builds, 2);
    expect(find.text('5'), findsOneWidget);

    controller.bumpOne('a');
    await tester.pump();
    expect(builds, 3);
  });

  testWidgets('update() from another widget\'s build is deferred',
      (tester) async {
    final controller = Get.put(Numbers());

    await tester.pumpWidget(Column(
      children: [
        GetBuilder<Numbers>(
          builder: (c) => Text('${c.value}', textDirection: TextDirection.ltr),
        ),
        Builder(builder: (_) {
          if (controller.value == 0) controller.bump();
          return const SizedBox();
        }),
      ],
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a deferred update() on an unmounted GetBuilder is dropped',
      (tester) async {
    final controller = Get.put(Numbers(), permanent: true);

    await tester.pumpWidget(Column(
      children: [
        GetBuilder<Numbers>(
          autoRemove: false,
          builder: (c) => Text('${c.value}', textDirection: TextDirection.ltr),
        ),
        Builder(builder: (_) {
          controller.bump();
          return const SizedBox();
        }),
      ],
    ));
    // The rebuild is queued in a microtask; unmount before it runs.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    expect(tester.takeException(), isNull);
    Get.delete<Numbers>(force: true);
  });

  testWidgets('updateAll() updates the id-less and the id-ed builders',
      (tester) async {
    final controller = Get.put(Numbers());
    var plainBuilds = 0;
    var idBuilds = 0;

    await tester.pumpWidget(Column(
      children: [
        GetBuilder<Numbers>(builder: (c) {
          plainBuilds++;
          return const SizedBox();
        }),
        GetBuilder<Numbers>(
            id: 'a',
            builder: (c) {
              idBuilds++;
              return const SizedBox();
            }),
      ],
    ));
    expect(plainBuilds, 1);
    expect(idBuilds, 1);

    // update() reaches the id-less builder only (original GetX behaviour).
    controller.bump();
    await tester.pump();
    expect(plainBuilds, 2);
    expect(idBuilds, 1);

    // updateAll() reaches both.
    controller.bumpAll();
    await tester.pump();
    expect(plainBuilds, 3);
    expect(idBuilds, 2);
  });

  testWidgets('updateAll() reaches every id', (tester) async {
    final controller = Get.put(Numbers());
    final builds = <Object, int>{'a': 0, 'b': 0, 'c': 0};

    await tester.pumpWidget(Column(
      children: [
        for (final id in builds.keys)
          GetBuilder<Numbers>(
              id: id,
              builder: (_) {
                builds[id] = builds[id]! + 1;
                return const SizedBox();
              }),
      ],
    ));
    expect(builds.values, everyElement(1));

    controller.updateAll();
    await tester.pump();
    expect(builds.values, everyElement(2));
  });

  testWidgets('updateAll(false) updates nothing', (tester) async {
    final controller = Get.put(Numbers());
    var plainBuilds = 0;
    var idBuilds = 0;

    await tester.pumpWidget(Column(
      children: [
        GetBuilder<Numbers>(builder: (_) {
          plainBuilds++;
          return const SizedBox();
        }),
        GetBuilder<Numbers>(
            id: 'a',
            builder: (_) {
              idBuilds++;
              return const SizedBox();
            }),
      ],
    ));

    controller.updateAll(false);
    await tester.pump();
    expect(plainBuilds, 1);
    expect(idBuilds, 1);
  });

  test('updateAll() survives a listener unlinking other ids', () {
    final controller = Numbers();
    final notified = <Object>[];

    // Each listener unlinks the other ids, i.e. the group map is mutated
    // while updateAll() iterates it. This used to throw
    // ConcurrentModificationError.
    for (final id in ['a', 'b', 'c']) {
      controller.addListenerId(id, () {
        notified.add(id);
        for (final other in ['a', 'b', 'c']) {
          if (other != id) controller.disposeId(other);
        }
      });
    }

    controller.updateAll();

    // Exactly one listener ran, and the other groups are gone.
    expect(notified, hasLength(1));
    for (final id in ['a', 'b', 'c']) {
      expect(controller.containsId(id), id == notified.single);
    }
  });
}
