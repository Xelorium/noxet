import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

// This callback remove the listener on addListener function
typedef Disposer = void Function();

// replacing StateSetter, return if the Widget is mounted for extra validation.
// if it brings overhead the extra call,
typedef GetStateUpdate = void Function();

class ListNotifier extends Listenable
    with ListNotifierSingleMixin, ListNotifierGroupMixin {}

/// A Notifier with single listeners
class ListNotifierSingle = ListNotifier with ListNotifierSingleMixin;

/// A notifier with group of listeners identified by id
class ListNotifierGroup = ListNotifier with ListNotifierGroupMixin;

/// Listeners of a [ListNotifierSingleMixin], in subscription order, with the
/// number of times each one was added.
///
/// Adding, removing and looking up a listener is O(1). Notifying iterates an
/// immutable [snapshot] that is rebuilt only after the listeners changed, so
/// listeners can subscribe or unsubscribe while being notified.
class _Listeners {
  // Map literals are insertion ordered (LinkedHashMap).
  final map = <GetStateUpdate, int>{};
  List<GetStateUpdate>? _snapshot;

  List<GetStateUpdate> get snapshot => _snapshot ??= List.unmodifiable([
    for (final entry in map.entries)
      for (var i = 0; i < entry.value; i++) entry.key,
  ]);

  void add(GetStateUpdate listener) {
    map[listener] = (map[listener] ?? 0) + 1;
    _snapshot = null;
  }

  void remove(GetStateUpdate listener) {
    final count = map[listener];
    if (count == null) return;
    if (count > 1) {
      map[listener] = count - 1;
    } else {
      map.remove(listener);
    }
    _snapshot = null;
  }
}

/// This mixin add to Listenable the addListener, removerListener and
/// containsListener implementation
mixin ListNotifierSingleMixin on Listenable {
  _Listeners? _updaters = _Listeners();

  @override
  Disposer addListener(GetStateUpdate listener) {
    assert(_debugAssertNotDisposed());
    _updaters!.add(listener);
    return () => removeListener(listener);
  }

  bool containsListener(GetStateUpdate listener) {
    return _updaters?.map.containsKey(listener) ?? false;
  }

  @override
  void removeListener(VoidCallback listener) {
    // Removing a listener from a disposed notifier is a no-op, so widgets
    // can safely unsubscribe after the observable has been closed.
    _updaters?.remove(listener);
  }

  @protected
  void refresh() {
    assert(_debugAssertNotDisposed());
    _notifyUpdate();
  }

  @protected
  void reportRead() {
    Notifier.instance.read(this);
  }

  @protected
  void reportAdd(VoidCallback disposer) {
    Notifier.instance.add(disposer);
  }

  void _notifyUpdate() {
    final updaters = _updaters;
    if (updaters == null || updaters.map.isEmpty) return;
    for (final listener in updaters.snapshot) {
      listener();
    }
  }

  bool get isDisposed => _updaters == null;

  bool _debugAssertNotDisposed() {
    assert(() {
      if (isDisposed) {
        throw FlutterError('''A $runtimeType was used after being disposed.\n
'Once you have called dispose() on a $runtimeType, it can no longer be used.''');
      }
      return true;
    }());
    return true;
  }

  int get listenersLength {
    assert(_debugAssertNotDisposed());
    var length = 0;
    for (final count in _updaters!.map.values) {
      length += count;
    }
    return length;
  }

  @mustCallSuper
  void dispose() {
    assert(_debugAssertNotDisposed());
    _updaters = null;
  }
}

mixin ListNotifierGroupMixin on Listenable {
  HashMap<Object?, ListNotifierSingleMixin>? _updatersGroupIds =
      HashMap<Object?, ListNotifierSingleMixin>();

  void _notifyGroupUpdate(Object id) {
    if (_updatersGroupIds!.containsKey(id)) {
      _updatersGroupIds![id]!._notifyUpdate();
    }
  }

  @protected
  void notifyGroupChildrens(Object id) {
    assert(_debugAssertNotDisposed());
    final updaters = _updatersGroupIds![id];
    if (updaters != null) Notifier.instance.read(updaters);
  }

  bool containsId(Object id) {
    return _updatersGroupIds?.containsKey(id) ?? false;
  }

  @protected
  void refreshGroup(Object id) {
    assert(_debugAssertNotDisposed());
    _notifyGroupUpdate(id);
  }

  bool _debugAssertNotDisposed() {
    assert(() {
      if (_updatersGroupIds == null) {
        throw FlutterError('''A $runtimeType was used after being disposed.\n
'Once you have called dispose() on a $runtimeType, it can no longer be used.''');
      }
      return true;
    }());
    return true;
  }

  void removeListenerId(Object id, VoidCallback listener) {
    _updatersGroupIds?[id]?.removeListener(listener);
  }

  @mustCallSuper
  void dispose() {
    assert(_debugAssertNotDisposed());
    _updatersGroupIds?.forEach((key, value) => value.dispose());
    _updatersGroupIds = null;
  }

  Disposer addListenerId(Object? key, GetStateUpdate listener) {
    assert(_debugAssertNotDisposed());
    _updatersGroupIds![key] ??= ListNotifierSingle();
    return _updatersGroupIds![key]!.addListener(listener);
  }

  /// To dispose an [id] from future updates(), this ids are registered
  /// by `GetBuilder()` or similar, so is a way to unlink the state change with
  /// the Widget from the Controller.
  void disposeId(Object id) {
    _updatersGroupIds?.remove(id)?.dispose();
  }
}

/// Runs [markNeedsBuild] now, or in a microtask when called while the
/// widget tree is being built (where marking an element dirty would throw).
/// [isMounted] is checked again before the deferred call.
void scheduleRebuild(VoidCallback markNeedsBuild, bool Function() isMounted) {
  if (SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks) {
    scheduleMicrotask(() {
      if (isMounted()) markNeedsBuild();
    });
  } else {
    markNeedsBuild();
  }
}

class Notifier {
  Notifier._();

  static Notifier? _instance;
  static Notifier get instance => _instance ??= Notifier._();

  NotifyData? _notifyData;

  void add(VoidCallback listener) {
    _notifyData?.disposers.add(listener);
  }

  /// The last notifier read by the current builder, to skip the lookup when
  /// the same observable is read repeatedly (e.g. iterating an RxList).
  ListNotifierSingleMixin? _lastRead;

  void read(ListNotifierSingleMixin updaters) {
    final data = _notifyData;
    if (data == null || identical(updaters, _lastRead)) return;
    _lastRead = updaters;
    final listener = data.updater;
    if (!updaters.containsListener(listener)) {
      data.disposers.add(updaters.addListener(listener));
    }
  }

  T append<T>(NotifyData data, T Function() builder) {
    final previous = _notifyData;
    final previousRead = _lastRead;
    _notifyData = data;
    _lastRead = null;
    try {
      final result = builder();
      if (data.disposers.isEmpty && data.throwException) {
        throw const ObxError();
      }
      return result;
    } finally {
      _notifyData = previous;
      _lastRead = previousRead;
    }
  }
}

class NotifyData {
  const NotifyData({
    required this.updater,
    required this.disposers,
    this.throwException = true,
  });
  final GetStateUpdate updater;
  final List<VoidCallback> disposers;
  final bool throwException;
}

class ObxError {
  const ObxError();
  @override
  String toString() {
    return """
      [Get] the improper use of a GetX has been detected. 
      You should only use GetX or Obx for the specific widget that will be updated.
      If you are seeing this error, you probably did not insert any observable variables into GetX/Obx 
      or insert them outside the scope that GetX considers suitable for an update 
      (example: GetX => HeavyWidget => variableObservable).
      If you need to update a parent widget and a child widget, wrap each one in an Obx/GetX.
      """;
  }
}
