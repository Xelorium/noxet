// "Page opens": GetBuilder(init:) registers the controller, Get runs its
// lifecycle, the widget subscribes and builds; closing the page deletes it.
//
// Uses only APIs that upstream get 5.0.0-rc-9.3.3 also has, so the same file
// can be run against it to compare.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

void printValue(String v) {
  // ignore: avoid_print
  print(v);
}

void measure(String name, int ops, void Function() body) {
  body();
  var best = -1;
  for (var run = 0; run < 5; run++) {
    final w = Stopwatch()..start();
    body();
    w.stop();
    if (best < 0 || w.elapsedMicroseconds < best) best = w.elapsedMicroseconds;
  }
  printValue('[$name] ${best}us (${(best * 1000 / ops).toStringAsFixed(0)} ns/op)');
}

Future<void> measureAsync(
    String name, int ops, Future<void> Function() body) async {
  await body();
  var best = -1;
  for (var run = 0; run < 5; run++) {
    final w = Stopwatch()..start();
    await body();
    w.stop();
    if (best < 0 || w.elapsedMicroseconds < best) best = w.elapsedMicroseconds;
  }
  printValue(
      '[$name] ${best}us (${(best / ops).toStringAsFixed(1)} us/page)');
}

class PageCtl extends GetxController {
  int inits = 0;
  int closes = 0;
  final items = <String>[];

  @override
  void onInit() {
    super.onInit();
    inits++;
  }

  @override
  void onClose() {
    closes++;
    super.onClose();
  }
}

Widget wrap(Widget child) =>
    Directionality(textDirection: TextDirection.ltr, child: child);

void main() {
  tearDown(Get.reset);

  // ---- Layer 1: the DI + lifecycle work a page open triggers, no widgets.
  // Low noise, this is the part the package owns.
  group('controller lifecycle without widgets', () {
    const n = 20000;

    test('put + find + delete', () {
      measure('put + find + delete', n, () {
        for (var i = 0; i < n; i++) {
          Get.put(PageCtl());
          Get.find<PageCtl>();
          Get.delete<PageCtl>();
        }
      });
    });

    test('lazyPut + find + delete (what GetBuilder(init:) does)', () {
      measure('lazyPut + find + delete', n, () {
        for (var i = 0; i < n; i++) {
          Get.lazyPut<PageCtl>(PageCtl.new);
          Get.find<PageCtl>();
          Get.delete<PageCtl>();
        }
      });
    });

    test('one create, many finds (a page with 10 lookups)', () {
      measure('1 put + 10 finds + delete', n, () {
        for (var i = 0; i < n; i++) {
          Get.put(PageCtl());
          for (var j = 0; j < 10; j++) {
            Get.find<PageCtl>();
          }
          Get.delete<PageCtl>();
        }
      });
    });
  });

  // ---- Layer 1b: the same work as a release build sees it. `Get.isLogEnable`
  // defaults to kDebugMode, so tests log on every registration; a shipped app
  // does not, and that is the path worth optimising.
  group('controller lifecycle, logging off (release-like)', () {
    const n = 20000;

    setUp(() => Get.isLogEnable = false);
    tearDown(() => Get.isLogEnable = true);

    test('lazyPut + find + delete', () {
      measure('release: lazyPut + find + delete', n, () {
        for (var i = 0; i < n; i++) {
          Get.lazyPut<PageCtl>(PageCtl.new);
          Get.find<PageCtl>();
          Get.delete<PageCtl>();
        }
      });
    });

    test('put + delete', () {
      final ctls = [for (var i = 0; i < n; i++) PageCtl()];
      measure('release: put + delete', n, () {
        for (var i = 0; i < n; i++) {
          Get.put(ctls[i]);
          Get.delete<PageCtl>();
        }
      });
    });

    test('1 put + 10 finds + delete', () {
      measure('release: 1 put + 10 finds + delete', n, () {
        for (var i = 0; i < n; i++) {
          Get.put(PageCtl());
          for (var j = 0; j < 10; j++) {
            Get.find<PageCtl>();
          }
          Get.delete<PageCtl>();
        }
      });
    });
  });

  // ---- Layer 2: the real thing. Dominated by Flutter's mount pipeline, so
  // treat small differences as noise.
  group('page open through widgets (noisy)', () {
    const pages = 200;

    testWidgets('GetBuilder(init:) creates and disposes the controller',
        (tester) async {
      await measureAsync('open+close page, 1 GetBuilder(init:)', pages,
          () async {
        for (var i = 0; i < pages; i++) {
          await tester.pumpWidget(wrap(GetBuilder<PageCtl>(
            init: PageCtl(),
            builder: (c) => Text('${c.items.length}'),
          )));
          await tester.pumpWidget(const SizedBox());
        }
      });
    });

    testWidgets('a page with 1 init and 9 more GetBuilders on it',
        (tester) async {
      await measureAsync('open+close page, 1 init + 9 GetBuilders', pages,
          () async {
        for (var i = 0; i < pages; i++) {
          await tester.pumpWidget(wrap(Column(children: [
            GetBuilder<PageCtl>(
              init: PageCtl(),
              builder: (c) => Text('${c.items.length}'),
            ),
            for (var j = 0; j < 9; j++)
              GetBuilder<PageCtl>(builder: (c) => Text('${c.items.length}')),
          ])));
          await tester.pumpWidget(const SizedBox());
        }
      });
    });

    testWidgets('page whose controller is already registered', (tester) async {
      Get.put(PageCtl(), permanent: true);
      await measureAsync('open+close page, controller already in memory', pages,
          () async {
        for (var i = 0; i < pages; i++) {
          await tester.pumpWidget(wrap(Column(children: [
            for (var j = 0; j < 10; j++)
              GetBuilder<PageCtl>(
                  autoRemove: false,
                  builder: (c) => Text('${c.items.length}')),
          ])));
          await tester.pumpWidget(const SizedBox());
        }
      });
    });
  });

  test('lifecycle actually ran', () {
    final c = Get.put(PageCtl());
    expect(c.inits, 1);
    Get.delete<PageCtl>();
    expect(c.closes, 1);
  });
}
