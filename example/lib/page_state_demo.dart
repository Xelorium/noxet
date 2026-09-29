/// GetBuilder + update() driven page states: loading, empty, error, data,
/// plus a custom state and a section that loads independently.
library;

import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// A state of your own, on top of the built-in five.
final class Paywalled extends PageCustomState<List<String>> {
  const Paywalled(this.remaining);

  final int remaining;
}

/// Stands in for an API. [mode] decides what the next call does.
enum Mode { data, empty, error, paywall }

class ArticlesController extends GetxController
    with PageStateMixin<List<String>> {
  /// Loads on its own, without touching the page state.
  late final comments = section<List<String>>('comments');

  Mode mode = Mode.data;

  @override
  void onInit() {
    super.onInit();
    fetch();
    fetchComments();
  }

  Future<void> fetch() => load(
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          switch (mode) {
            case Mode.error:
              throw 'The server said no';
            case Mode.empty:
              return <String>[];
            case Mode.paywall:
              return <String>['paywalled'];
            case Mode.data:
              return ['Reactive Dart', 'Sealed classes', 'GetBuilder tips'];
          }
        },
        // A load can end in a state of your own instead of plain data.
        mapState: (articles) =>
            mode == Mode.paywall ? const Paywalled(3) : null,
      );

  /// Keeps the current list on screen while refetching, like pull-to-refresh.
  Future<void> refreshArticles() => load(() async {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        return ['Refreshed', 'Second item'];
      }, keepDataWhileLoading: true);

  Future<void> fetchComments() => comments.load(() async {
        await Future<void>.delayed(const Duration(milliseconds: 900));
        return ['Nice write-up', 'Bookmarked'];
      });

  void setMode(Mode value) {
    mode = value;
    fetch();
  }
}

class PageStateDemoPage extends StatelessWidget {
  const PageStateDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page state')),
      body: GetBuilder<ArticlesController>(
        init: ArticlesController(),
        builder: (controller) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final mode in Mode.values)
                    ChoiceChip(
                      label: Text(mode.name),
                      selected: controller.mode == mode,
                      onSelected: (_) => controller.setMode(mode),
                    ),
                  ActionChip(
                    label: const Text('refresh'),
                    onPressed: controller.refreshArticles,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // The page state. Only onData is required; the rest fall back to
            // PageStateDefaults and then to built-ins.
            Expanded(
              child: PageStateView<ArticlesController, List<String>>(
                onData: (context, articles) => ListView(
                  children: [
                    for (final article in articles)
                      ListTile(title: Text(article)),
                  ],
                ),
                onEmpty: (context, state) =>
                    const Center(child: Text('No articles yet')),
                onFailure: (context, state) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${state.errorOrNull}'),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: controller.retry,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                // Your own states are matched here.
                onCustom: (context, state) => switch (state) {
                  Paywalled(:final remaining) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$remaining free articles left'),
                          TextButton(
                            onPressed: () => controller.setMode(Mode.data),
                            child: const Text('Subscribe'),
                          ),
                        ],
                      ),
                    ),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),

            const Divider(height: 1),

            // An independent section: update(['comments']) only rebuilds this.
            SizedBox(
              height: 130,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Comments',
                            style: Theme.of(context).textTheme.titleSmall),
                        TextButton(
                          onPressed: controller.fetchComments,
                          child: const Text('Reload section'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageSectionView<ArticlesController, List<String>>(
                      id: 'comments',
                      select: (controller) => controller.comments,
                      onData: (context, comments) => ListView(
                        children: [
                          for (final comment in comments)
                            ListTile(dense: true, title: Text(comment)),
                        ],
                      ),
                      onEmpty: (context, state) =>
                          const Center(child: Text('No comments')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
