# get (state management)

A slimmed-down fork of [GetX](https://github.com/jonataslaw/getx) that keeps
only **state management** and **dependency injection**. Navigation, HTTP /
WebSocket clients, animations, internationalization and utility extensions
have been removed. The package name and public API (`package:get/get.dart`,
`Obx`, `GetBuilder`, `Get.put`, ...) are unchanged, so existing state
management code keeps working.

What is included:

- Reactive state: `.obs`, `Rx<T>`, `RxList`, `RxMap`, `RxSet`, `Obx`, `ObxValue`, `GetX`
- Simple state: `GetxController.update()`, `updateAll()`, `GetBuilder`,
  `ValueBuilder`
- Page states: `PageStateMixin`, `PageState` (loading / empty / error / data /
  your own), `PageStateView`, `PageSectionView`
- Async state: `StateMixin`, `GetStatus`, `futurize`, `obx()`
- Workers: `ever`, `once`, `debounce`, `interval`, `everAll`
- Dependency injection: `Get.put`, `Get.lazyPut`, `Get.putAsync`, `Get.create`,
  `Get.find`, `Get.delete`, `Get.reset`, `Bind`, `Binds`, `Binding`
- Views and lifecycle: `GetView`, `GetWidget`, `GetxService`, `SmartManagement`

- [Installing](#installing)
- [Counter example](#counter-example)
- [Reactive state](#reactive-state)
- [Simple state](#simple-state)
- [Page states](#page-states)
- [StateMixin](#statemixin)
- [Workers](#workers)
- [Dependency injection](#dependency-injection)
- [Tests](#tests)

# Installing

```yaml
dependencies:
  get:
    git:
      url: https://github.com/xelorium/noxet.git
```

```dart
import 'package:get/get.dart';
```

`package:get/state_manager.dart` and `package:get/instance_manager.dart` are
also available if you only need part of the package.

# Counter example

No `GetMaterialApp` is needed, any `MaterialApp`/`CupertinoApp`/`WidgetsApp`
works.

```dart
void main() => runApp(MaterialApp(home: Home()));

class Controller extends GetxController {
  final count = 0.obs;
  void increment() => count.value++;
}

class Home extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = Get.put(Controller());

    return Scaffold(
      appBar: AppBar(title: Obx(() => Text('Clicks: ${c.count}'))),
      floatingActionButton: FloatingActionButton(
        onPressed: c.increment,
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

A fuller example lives in [`example/`](./example).

# Reactive state

Make any value observable with `.obs` and read it inside `Obx`; the widget
rebuilds only when a value it read changes.

```dart
final name = 'Jonatas'.obs;
final items = <String>[].obs;

Obx(() => Text('${name.value} has ${items.length} items'));

name.value = 'Borges'; // rebuilds
items.add('apple');    // rebuilds
```

`ObxValue` keeps an observable local to a widget:

```dart
ObxValue<RxBool>(
  (data) => Switch(value: data.value, onChanged: data),
  false.obs,
);
```

# Simple state

Call `update()` in a `GetxController` to rebuild every `GetBuilder` of that
controller (or only the ones with a given `id`). `update()` does **not** reach
the `GetBuilder`s that were given an `id`; use `updateAll()` to rebuild both
the id-less and the id-ed ones.

```dart
class TodoController extends GetxController {
  final todos = <String>[];

  void add(String todo) {
    todos.add(todo);
    update();
  }
}

GetBuilder<TodoController>(
  init: TodoController(),
  builder: (c) => Text('${c.todos.length} todos'),
);
```

`ValueBuilder` is a lightweight replacement for a `StatefulWidget` holding a
single value:

```dart
ValueBuilder<bool>(
  initialValue: false,
  builder: (value, update) => Switch(value: value, onChanged: update),
);
```

# Page states

`PageStateMixin` gives a controller the loading / empty / error / data states a
page goes through, driven by `update()` so it works with `GetBuilder` rather
than `Obx`. States are a sealed hierarchy, so a `switch` over them is
exhaustive, and `PageCustomState` is the extension point for states of your
own.

```dart
class ArticlesController extends GetxController
    with PageStateMixin<List<Article>> {
  /// Loads on its own; update(['comments']) rebuilds only this section.
  late final comments = section<List<Comment>>('comments');

  @override
  void onInit() {
    super.onInit();
    load(() => api.articles());
    comments.load(() => api.comments());
  }
}

PageStateView<ArticlesController, List<Article>>(
  init: ArticlesController(),
  onData: (context, articles) => ArticleList(articles),
  onEmpty: (context, state) => const Text('Nothing here yet'),
  onFailure: (context, state) => RetryBox(onTap: controller.retry),
);
```

`load()` moves through `PageLoading` to `PageData`, `PageEmpty` or
`PageFailure`, drops the result of a call that a newer one superseded, and
`retry()` replays the last one. `keepDataWhileLoading: true` keeps the current
list on screen for a pull-to-refresh, and `mapState:` lets a load end in a
state of your own.

Define extra states by extending `PageCustomState`:

```dart
final class Paywalled extends PageCustomState<List<Article>> {
  const Paywalled(this.remaining);
  final int remaining;
}

switch (controller.state) {
  Paywalled(:final remaining) => Paywall(remaining),  // before the broad case
  PageCustomState() => const SizedBox.shrink(),
  PageData(:final value) => ArticleList(value),
  PageLoading() => const Spinner(),
  PageIdle() || PageEmpty() => const EmptyView(),
  PageFailure(:final error) => ErrorView(error),
}
```

> Do not name a controller method `refresh()`. `GetxController` already has
> one and `update()` calls it; because `void` is a top type in Dart, even
> `Future<void> refresh()` silently overrides it and every state change
> re-enters your method. Use `refreshData()` or similar.

# StateMixin

```dart
class UserController extends GetxController with StateMixin<User> {
  @override
  void onInit() {
    super.onInit();
    futurize(api.fetchUser); // loading -> success / empty / error
  }
}

class UserView extends GetView<UserController> {
  @override
  Widget build(BuildContext context) {
    return controller.obx(
      (user) => Text(user.name),
      onLoading: const CircularProgressIndicator(),
      onEmpty: const Text('No user'),
      onError: (error) => Text('$error'),
    );
  }
}
```

You can also set the state manually with `change(GetStatus.success(user))`,
`GetStatus.loading()`, `GetStatus.empty()` or `GetStatus.error(error)`.

# Workers

Workers react to changes of an observable. Dispose them (or let the
controller do it in `onClose`) when they are no longer needed.

```dart
ever(count, (value) => print('changed to $value'));
once(count, (value) => print('first change'));
debounce(query, search, time: const Duration(milliseconds: 300));
interval(count, (value) => print('at most once per second'),
    time: const Duration(seconds: 1));
```

# Dependency injection

```dart
Get.put(ApiService(), permanent: true);
Get.lazyPut(() => HomeController());      // created on first find
Get.lazyPut(() => Repo(), fenix: true);   // re-created after being deleted
await Get.putAsync(() => Db.open());
Get.create(() => ItemController());       // new instance on every find

final home = Get.find<HomeController>();
Get.delete<HomeController>();
```

Dependencies can also be scoped to a subtree:

```dart
class HomeBinding extends Binding {
  @override
  List<Bind> dependencies() => [
        Bind.lazyPut(() => HomeController()),
      ];
}

Binds(binds: HomeBinding().dependencies(), child: const HomePage());
```

`GetView<T>` exposes `controller` (`Get.find<T>()`), `GetWidget<T>` caches a
controller created with `Get.create`, and `GetxService` is never removed
except by `Get.reset()`.

`Get.smartManagement` controls how unused dependencies are removed:
`SmartManagement.full` (default), `SmartManagement.onlyBuilder` or
`SmartManagement.keepFactory`.

More details: [state management](./documentation/en_US/state_management.md),
[dependency management](./documentation/en_US/dependency_management.md).

# Tests

Controllers are plain classes and their lifecycle can be tested directly:

```dart
test('lifecycle', () {
  final controller = Controller();
  Get.put(controller);          // onInit is called
  controller.increment();
  expect(controller.count.value, 1);
  Get.delete<Controller>();     // onClose is called
});

tearDown(Get.reset);
```
