import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'init_benchmark.dart';
import 'phase4_demo.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'get state management',
      home: Binds(
        binds: HomeBinding().dependencies(),
        child: const HomePage(),
      ),
    );
  }
}

class HomeBinding extends Binding {
  @override
  List<Bind> dependencies() => [
        Bind.lazyPut<CounterController>(() => CounterController()),
        Bind.lazyPut<TodoController>(() => TodoController()),
        Bind.lazyPut<QuoteController>(() => QuoteController()),
      ];
}

/// Reactive state: `.obs` + `Obx`.
class CounterController extends GetxController {
  final count = 0.obs;

  void increment() => count.value++;
}

/// Simple state: `update()` + `GetBuilder`.
class TodoController extends GetxController {
  final todos = <String>[];

  void add(String todo) {
    todos.add(todo);
    update();
  }

  void removeAt(int index) {
    todos.removeAt(index);
    update();
  }
}

/// Async state: `StateMixin` + `futurize` + `obx`.
class QuoteController extends GetxController with StateMixin<String> {
  int _next = 0;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  void load() {
    futurize(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      const quotes = ['Keep it simple.', 'Make it work, then make it fast.'];
      return quotes[_next++ % quotes.length];
    });
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final counter = Get.find<CounterController>();
    final quote = Get.find<QuoteController>();

    return Scaffold(
      appBar: AppBar(title: const Text('get state management')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Obx(() => Text('Count: ${counter.count.value}',
              style: Theme.of(context).textTheme.headlineSmall)),
          const Divider(),
          quote.obx(
            (value) => Text(value),
            onLoading: const LinearProgressIndicator(),
            onError: (error) => Text('Error: $error'),
          ),
          TextButton(onPressed: quote.load, child: const Text('Next quote')),
          const Divider(),
          GetBuilder<TodoController>(
            builder: (controller) => Column(
              children: [
                for (var i = 0; i < controller.todos.length; i++)
                  ListTile(
                    title: Text(controller.todos[i]),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => controller.removeAt(i),
                    ),
                  ),
                TextButton(
                  onPressed: () => controller
                      .add('Todo ${controller.todos.length + 1}'),
                  child: const Text('Add todo'),
                ),
              ],
            ),
          ),
          const Divider(),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Phase4DemoPage(),
              ),
            ),
            child: const Text('GetBuilder / Get.find demo'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const InitBenchmarkPage(),
              ),
            ),
            child: const Text('Page open benchmark'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: counter.increment,
        child: const Icon(Icons.add),
      ),
    );
  }
}
