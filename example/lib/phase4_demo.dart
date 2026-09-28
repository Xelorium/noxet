/// A page that exercises the five GetBuilder / Get.find improvements:
///
/// 1. `update()` called while the tree is building defers the rebuild.
/// 2. `Get.find` throws a typed `GetInstanceNotFoundError`.
/// 3. A second `Get.put` of the same type warns in debug mode.
/// 4. `Get.find` is keyed by a record, so lookups are cheap.
/// 5. `updateAll()` reaches the `GetBuilder`s that have an `id`.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// (1) A controller that finishes its own initialization from inside a build.
class LazyLabelController extends GetxController {
  String? label;
  int builds = 0;

  /// Called from a `GetBuilder` builder, i.e. while the tree is being built.
  /// Before the fix this threw
  /// "setState() or markNeedsBuild() called during build".
  void ensureLabel() {
    if (label == null) {
      label = 'resolved during build';
      update();
    }
  }

  void reset() {
    label = null;
    update();
  }
}

/// (5) A controller read by both id-less and id-ed `GetBuilder`s.
class PanelsController extends GetxController {
  int version = 0;

  void bumpPlain() {
    version++;
    update();
  }

  void bumpOne(Object id) {
    version++;
    update([id]);
  }

  void bumpEverything() {
    version++;
    updateAll();
  }
}

/// (2) Deliberately never registered.
class NeverRegistered extends GetxController {}

/// (3) Registered twice, to trigger the duplicate warning.
class Duplicated extends GetxController {
  Duplicated(this.label);
  final String label;
}

class Phase4DemoPage extends StatefulWidget {
  const Phase4DemoPage({super.key});

  @override
  State<Phase4DemoPage> createState() => _Phase4DemoPageState();
}

class _Phase4DemoPageState extends State<Phase4DemoPage> {
  String? findError;
  String? duplicateReport;
  String? findTiming;

  @override
  void initState() {
    super.initState();
    Get.put(LazyLabelController());
    Get.put(PanelsController());
  }

  @override
  void dispose() {
    Get.delete<LazyLabelController>();
    Get.delete<PanelsController>();
    super.dispose();
  }

  // (2) Catch the typed error and read its fields.
  void findMissing() {
    try {
      Get.find<NeverRegistered>(tag: 'nope');
      setState(() => findError = 'no error (unexpected)');
    } on GetInstanceNotFoundError catch (error, stack) {
      setState(() {
        findError = 'GetInstanceNotFoundError\n'
            'type: ${error.type}\n'
            'tag: ${error.tag}\n'
            'stack trace: ${stack.toString().isNotEmpty ? 'yes' : 'no'}\n'
            '${error.toString()}';
      });
    }
  }

  // (3) Put the same type twice and capture what Get logged.
  void putTwice() {
    final logged = <String>[];
    final previousLog = Get.log;
    Get.log = (String text, {bool isError = false}) {
      if (isError) logged.add(text);
      previousLog(text, isError: isError);
    };

    final first = Get.put(Duplicated('first'));
    final second = Duplicated('second');
    final returned = Get.put(second);

    Get.log = previousLog;
    Get.delete<Duplicated>();

    setState(() {
      duplicateReport = 'first put: ${first.label}\n'
          'second put returned: ${returned.label}\n'
          'discarded instance initialized: ${second.initialized}\n'
          '${logged.isEmpty ? kDebugMode ? 'no warning (unexpected)' : 'warning is debug-only, this is a release build' : 'warning: ${logged.single}'}';
    });
  }

  // (4) Time the lookup that GetView.controller performs on every access.
  void timeFind() {
    const iterations = 100000;
    Get.put(LazyLabelController(), tag: 'benchmark');

    void run(String? tag) {
      for (var i = 0; i < iterations; i++) {
        Get.find<LazyLabelController>(tag: tag);
      }
    }

    run(null); // warm up
    final plain = Stopwatch()..start();
    run(null);
    plain.stop();

    final tagged = Stopwatch()..start();
    run('benchmark');
    tagged.stop();

    Get.delete<LazyLabelController>(tag: 'benchmark');

    String perCall(Stopwatch watch) =>
        '${(watch.elapsedMicroseconds * 1000 / iterations).toStringAsFixed(0)} ns';

    setState(() {
      findTiming = '$iterations lookups\n'
          'Get.find<T>(): ${plain.elapsedMilliseconds} ms '
          '(${perCall(plain)}/call)\n'
          'Get.find<T>(tag:): ${tagged.elapsedMilliseconds} ms '
          '(${perCall(tagged)}/call)';
    });
  }

  @override
  Widget build(BuildContext context) {
    final panels = Get.find<PanelsController>();

    return Scaffold(
      appBar: AppBar(title: const Text('GetBuilder / Get.find')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: '1. update() during build',
            description: 'The builder finishes the controller\'s setup and '
                'calls update() while the tree is building. The rebuild is '
                'deferred instead of throwing.',
            child: GetBuilder<LazyLabelController>(
              builder: (controller) {
                controller.builds++;
                controller.ensureLabel();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('label: ${controller.label ?? 'not resolved yet'}'),
                    Text('builds: ${controller.builds}'),
                    TextButton(
                      onPressed: controller.reset,
                      child: const Text('Reset and rebuild'),
                    ),
                  ],
                );
              },
            ),
          ),
          _Section(
            title: '2. Typed error from Get.find',
            description: 'An unregistered lookup throws '
                'GetInstanceNotFoundError, which carries a stack trace.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton(
                  onPressed: findMissing,
                  child: const Text('Find an unregistered controller'),
                ),
                if (findError != null) _Output(findError!),
              ],
            ),
          ),
          _Section(
            title: '3. Duplicate Get.put warns',
            description: 'The first instance is kept and the second is '
                'discarded without ever being initialized. In debug mode '
                'that is now logged instead of silent.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton(
                  onPressed: putTwice,
                  child: const Text('Put the same type twice'),
                ),
                if (duplicateReport != null) _Output(duplicateReport!),
              ],
            ),
          ),
          _Section(
            title: '4. Get.find cost',
            description: 'Registrations are keyed by a (Type, tag) record, so '
                'a lookup builds no string and hits the map once. Run this in '
                'a release build for representative numbers.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton(
                  onPressed: timeFind,
                  child: const Text('Time 100000 lookups'),
                ),
                if (findTiming != null) _Output(findTiming!),
              ],
            ),
          ),
          _Section(
            title: '5. updateAll()',
            description: 'update() never reaches a GetBuilder that has an id. '
                'updateAll() reaches the id-less one and every id at once. '
                'Watch the build counts.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Panel(id: null),
                const _Panel(id: 'a'),
                const _Panel(id: 'b'),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: panels.bumpPlain,
                      child: const Text('update()'),
                    ),
                    TextButton(
                      onPressed: () => panels.bumpOne('a'),
                      child: const Text("update(['a'])"),
                    ),
                    TextButton(
                      onPressed: panels.bumpEverything,
                      child: const Text('updateAll()'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One `GetBuilder` on [PanelsController], with or without an [id].
class _Panel extends StatefulWidget {
  const _Panel({required this.id});

  final Object? id;

  @override
  State<_Panel> createState() => _PanelState();
}

class _PanelState extends State<_Panel> {
  int builds = 0;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<PanelsController>(
      id: widget.id,
      autoRemove: false,
      builder: (controller) {
        builds++;
        final label = widget.id == null ? 'no id' : "id '${widget.id}'";
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text('$label — builds: $builds, '
              'version seen: ${controller.version}'),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _Output extends StatelessWidget {
  const _Output(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(text, style: const TextStyle(fontFamily: 'monospace')),
    );
  }
}
