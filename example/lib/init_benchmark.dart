/// On-device benchmark for the "page opens, Get creates the controller" path.
///
/// Run it in release mode (`flutter run --release`) for meaningful numbers.
/// In debug the Dart VM is far slower and `Get.isLogEnable` defaults to true,
/// which is itself most of the cost.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class BenchController extends GetxController {
  int inits = 0;
  final items = <String>[];

  @override
  void onInit() {
    super.onInit();
    inits++;
  }
}

/// Best of 5 runs after a warm-up, in nanoseconds per operation.
double _measure(int ops, void Function() body) {
  body();
  var best = -1;
  for (var run = 0; run < 5; run++) {
    final watch = Stopwatch()..start();
    body();
    watch.stop();
    if (best < 0 || watch.elapsedMicroseconds < best) {
      best = watch.elapsedMicroseconds;
    }
  }
  return best * 1000 / ops;
}

class InitBenchmarkPage extends StatefulWidget {
  const InitBenchmarkPage({super.key});

  @override
  State<InitBenchmarkPage> createState() => _InitBenchmarkPageState();
}

class _InitBenchmarkPageState extends State<InitBenchmarkPage> {
  final rows = <String, double>{};
  String? pageOpen;
  bool running = false;
  int iterations = 20000;

  /// The three shapes of work a page open triggers, measured with logging in
  /// whatever state [logEnabled] asks for.
  void _runDi({required bool logEnabled}) {
    final previous = Get.isLogEnable;
    Get.isLogEnable = logEnabled;
    final suffix = logEnabled ? 'log on' : 'log off';
    final n = iterations;

    rows['lazyPut + find + delete ($suffix)'] = _measure(n, () {
      for (var i = 0; i < n; i++) {
        Get.lazyPut<BenchController>(BenchController.new);
        Get.find<BenchController>();
        Get.delete<BenchController>();
      }
    });

    final ctls = [for (var i = 0; i < n; i++) BenchController()];
    rows['put + delete ($suffix)'] = _measure(n, () {
      for (var i = 0; i < n; i++) {
        Get.put(ctls[i]);
        Get.delete<BenchController>();
      }
    });

    rows['1 put + 10 finds + delete ($suffix)'] = _measure(n, () {
      for (var i = 0; i < n; i++) {
        Get.put(BenchController());
        for (var j = 0; j < 10; j++) {
          Get.find<BenchController>();
        }
        Get.delete<BenchController>();
      }
    });

    Get.isLogEnable = previous;
  }

  Future<void> runAll() async {
    setState(() => running = true);
    // Let the frame with the spinner land before blocking the isolate.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    rows.clear();
    _runDi(logEnabled: false);
    _runDi(logEnabled: true);
    setState(() => running = false);
  }

  /// Real page open: push a route holding one GetBuilder(init:) plus nine more
  /// GetBuilders, and stop the clock on that page's first frame.
  Future<void> measurePageOpen() async {
    const opens = 30;
    var total = 0;
    for (var i = 0; i < opens; i++) {
      final watch = Stopwatch()..start();
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _MeasuredPage(onFirstFrame: () {
          watch.stop();
          total += watch.elapsedMicroseconds;
        }),
      ));
    }
    setState(() => pageOpen =
        '${(total / opens / 1000).toStringAsFixed(2)} ms per open '
        '(avg of $opens, includes the frame)');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Page open benchmark')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kReleaseMode
                        ? 'Release build — numbers are representative.'
                        : 'DEBUG build. The VM is much slower here and Get '
                            'logs on every registration. Re-run with '
                            'flutter run --release.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: kReleaseMode ? null : theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Get.isLogEnable defaults to ${Get.isLogEnable}'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: running ? null : runAll,
                  child: Text(running ? 'Running…' : 'Run DI benchmark'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: running ? null : measurePageOpen,
                  child: const Text('Measure page open'),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Text('iterations: '),
              for (final n in [5000, 20000, 50000])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$n'),
                    selected: iterations == n,
                    onSelected: running
                        ? null
                        : (_) => setState(() => iterations = n),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (pageOpen != null) ...[
            Text('Page open', style: theme.textTheme.titleSmall),
            Text(pageOpen!),
            const Divider(),
          ],
          if (rows.isNotEmpty) ...[
            Text('Per operation', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final entry in rows.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(entry.key)),
                    Text('${entry.value.toStringAsFixed(0)} ns',
                        style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'The "log off" rows are what a release app pays. Building the '
              'log strings used to happen even when logging was disabled.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// A page shaped like a real one: one GetBuilder creates the controller, the
/// rest just read it.
class _MeasuredPage extends StatelessWidget {
  const _MeasuredPage({required this.onFirstFrame});

  final VoidCallback onFirstFrame;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onFirstFrame();
      if (context.mounted) Navigator.of(context).pop();
    });
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GetBuilder<BenchController>(
            init: BenchController(),
            builder: (c) => Text('created, inits: ${c.inits}'),
          ),
          for (var i = 0; i < 9; i++)
            GetBuilder<BenchController>(
              builder: (c) => Text('reader $i: ${c.items.length}'),
            ),
        ],
      ),
    );
  }
}
