import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

class Articles extends GetxController with PageStateMixin<List<String>> {
  late final comments = section<List<String>>('comments');
}

final class Paywalled extends PageCustomState<List<String>> {
  const Paywalled(this.remaining);

  final int remaining;
}

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  tearDown(Get.reset);

  Widget page({
    Articles? init,
    PageStateWidgetBuilder<List<String>>? onEmpty,
    PageStateWidgetBuilder<List<String>>? onFailure,
    PageStateWidgetBuilder<List<String>>? onLoading,
    PageStateWidgetBuilder<List<String>>? onIdle,
    PageStateWidgetBuilder<List<String>>? onCustom,
  }) =>
      wrap(PageStateView<Articles, List<String>>(
        init: init,
        onData: (_, value) => Text('data ${value.length}'),
        onIdle: onIdle,
        onLoading: onLoading,
        onEmpty: onEmpty,
        onFailure: onFailure,
        onCustom: onCustom,
      ));

  testWidgets('renders each branch as the state moves', (tester) async {
    final controller = Get.put(Articles());
    await tester.pumpWidget(page(
      onIdle: (_, _) => const Text('idle'),
      onEmpty: (_, state) => Text('empty ${(state as PageEmpty).message}'),
      onFailure: (_, state) => Text('failure ${state.errorOrNull}'),
    ));
    expect(find.text('idle'), findsOneWidget);

    controller.setLoading();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    controller.setData(['a', 'b']);
    await tester.pump();
    expect(find.text('data 2'), findsOneWidget);

    controller.setEmpty(message: 'none');
    await tester.pump();
    expect(find.text('empty none'), findsOneWidget);

    controller.setFailure('boom');
    await tester.pump();
    expect(find.text('failure boom'), findsOneWidget);
  });

  testWidgets('init creates and registers the controller', (tester) async {
    expect(Get.isRegistered<Articles>(), isFalse);
    await tester.pumpWidget(page(init: Articles()));
    expect(Get.isRegistered<Articles>(), isTrue);

    Get.find<Articles>().setData(['a']);
    await tester.pump();
    expect(find.text('data 1'), findsOneWidget);
  });

  testWidgets('a user defined custom state reaches onCustom', (tester) async {
    final controller = Get.put(Articles());
    await tester.pumpWidget(page(
      onCustom: (_, state) => switch (state) {
        Paywalled(:final remaining) => Text('paywall $remaining'),
        _ => const Text('other custom'),
      },
    ));

    controller.setCustom(const Paywalled(3));
    await tester.pump();
    expect(find.text('paywall 3'), findsOneWidget);
  });

  testWidgets('built-in fallbacks cover the branches left out',
      (tester) async {
    final controller = Get.put(Articles());
    await tester.pumpWidget(page());

    // Idle and empty collapse to nothing, loading spins, failure prints.
    expect(find.byType(SizedBox), findsWidgets);

    controller.setFailure('kaboom');
    await tester.pump();
    expect(find.text('kaboom'), findsOneWidget);
  });

  testWidgets('PageStateDefaults supplies the app-wide fallbacks',
      (tester) async {
    final controller = Get.put(Articles());
    await tester.pumpWidget(PageStateDefaults(
      loading: (_, _) => const Text('shared loading'),
      failure: (_, state) => Text('shared ${state.errorOrNull}'),
      child: page(),
    ));

    controller.setLoading();
    await tester.pump();
    expect(find.text('shared loading'), findsOneWidget);

    controller.setFailure('oops');
    await tester.pump();
    expect(find.text('shared oops'), findsOneWidget);
  });

  testWidgets('a per-page builder wins over PageStateDefaults',
      (tester) async {
    final controller = Get.put(Articles());
    await tester.pumpWidget(PageStateDefaults(
      loading: (_, _) => const Text('shared loading'),
      child: page(onLoading: (_, _) => const Text('page loading')),
    ));

    controller.setLoading();
    await tester.pump();
    expect(find.text('page loading'), findsOneWidget);
    expect(find.text('shared loading'), findsNothing);
  });

  group('PageSectionView', () {
    Widget sectioned({required void Function() onPageBuild}) =>
        wrap(Column(children: [
          PageStateView<Articles, List<String>>(
            onData: (_, value) {
              onPageBuild();
              return Text('page ${value.length}');
            },
            onIdle: (_, _) {
              onPageBuild();
              return const Text('page idle');
            },
          ),
          PageSectionView<Articles, List<String>>(
            id: 'comments',
            select: (controller) => controller.comments,
            onData: (_, value) => Text('comments ${value.length}'),
            onIdle: (_, _) => const Text('comments idle'),
          ),
        ]));

    testWidgets('renders its own holder and starts idle', (tester) async {
      Get.put(Articles());
      await tester.pumpWidget(sectioned(onPageBuild: () {}));
      expect(find.text('page idle'), findsOneWidget);
      expect(find.text('comments idle'), findsOneWidget);
    });

    testWidgets('updating a section leaves the page alone', (tester) async {
      final controller = Get.put(Articles());
      var pageBuilds = 0;
      await tester.pumpWidget(sectioned(onPageBuild: () => pageBuilds++));
      final before = pageBuilds;

      controller.comments.setData(['c1', 'c2']);
      await tester.pump();

      expect(find.text('comments 2'), findsOneWidget);
      expect(find.text('page idle'), findsOneWidget);
      expect(pageBuilds, before, reason: 'the page must not rebuild');
    });

    testWidgets('updating the page leaves the section alone', (tester) async {
      final controller = Get.put(Articles());
      await tester.pumpWidget(sectioned(onPageBuild: () {}));

      controller.comments.setData(['c1']);
      await tester.pump();
      controller.setData(['a']);
      await tester.pump();

      expect(find.text('page 1'), findsOneWidget);
      expect(find.text('comments 1'), findsOneWidget);
    });
  });
}
