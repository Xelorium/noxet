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
}
