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
/// Adding, removing and looking up a listener is O(1). Notifying iterates a
/// cached [snapshot], so listeners can subscribe or unsubscribe while being
/// notified: a notification keeps its own reference to the list it started
/// with, and a change during it only invalidates the cache for the next one.
class _Listeners {
  // Map literals are insertion ordered (LinkedHashMap).
  final map = <GetStateUpdate, int>{};
  List<GetStateUpdate>? _snapshot;

  /// How many notifications are currently iterating [_snapshot].
  int _notifying = 0;

  /// The sole listener, when there is exactly one. Notifying then needs no
  /// snapshot at all, which is the common case: one `Obx` or one worker on an
  /// observable.
  GetStateUpdate? _only;

  List<GetStateUpdate> get snapshot => _snapshot ??= [
    for (final entry in map.entries)
      for (var i = 0; i < entry.value; i++) entry.key,
  ];

  void add(GetStateUpdate listener) {
    // One hash lookup instead of a read followed by a write: hashing a
    // closure is the dominant cost of subscribing.
    final count = map.update(listener, (value) => value + 1, ifAbsent: () => 1);
    // Cheap to keep up to date here: no iteration needed to know whether this
    // is still the only listener.
    _only = map.length == 1 && count == 1 ? listener : null;

    final snapshot = _snapshot;
    if (snapshot == null) return;
    if (_notifying > 0) {
      // In use by a notification: leave that list alone and rebuild later.
      _snapshot = null;
    } else {
      // Extend the cache instead of discarding it, so subscribing between
      // notifications does not make the next one rebuild the whole list.
      // A repeat of the same listener lands at the end rather than next to
      // its twin; they are the same callback, so the order does not matter.
      snapshot.add(listener);
    }
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
    // Removing is rare, so recomputing the shortcut by inspecting the
    // remaining entry is fine here.
    if (map.length == 1) {
      final entry = map.entries.first;
      _only = entry.value == 1 ? entry.key : null;
    } else {
      _only = null;
    }
  }

  void notify() {
    final only = _only;
    if (only != null) {
      only();
      return;
    }
    if (map.isEmpty) return;
    // Keep a local reference: a listener may subscribe during the loop, which
    // invalidates the cache but must not disturb this iteration.
    final listeners = snapshot;
    _notifying++;
    try {
      for (var i = 0; i < listeners.length; i++) {
        listeners[i]();
      }
    } finally {
      _notifying--;
    }
  }
}

/// This mixin add to Listenable the addListener, removerListener and
/// containsListener implementation
mixin ListNotifierSingleMixin on Listenable {
  /// The listener, while there is exactly one. Holding it inline keeps the
  /// common case — a single `Obx` or worker on an observable — free of the
  /// listener map entirely.
  GetStateUpdate? _single;

  /// Created once a second listener arrives. Most observables never get one,
  /// and allocating the map up front cost more than its O(1) lookups save.
  _Listeners? _updaters;

  bool _disposed = false;

  @override
  Disposer addListener(GetStateUpdate listener) {
    assert(_debugAssertNotDisposed());
    final updaters = _updaters;
    if (updaters != null) {
      updaters.add(listener);
    } else {
      final single = _single;
      if (single == null) {
        _single = listener;
      } else {
        // A second listener (or the same one twice): switch to the map.
        _updaters = _Listeners()
          ..add(single)
          ..add(listener);
        _single = null;
      }
    }
    return () => removeListener(listener);
  }

  bool containsListener(GetStateUpdate listener) {
    final updaters = _updaters;
    if (updaters != null) return updaters.map.containsKey(listener);
    return _single == listener;
  }

  @override
  void removeListener(VoidCallback listener) {
    // Removing a listener from a disposed notifier is a no-op, so widgets
    // can safely unsubscribe after the observable has been closed.
    final updaters = _updaters;
    if (updaters != null) {
      updaters.remove(listener);
    } else if (_single == listener) {
      _single = null;
    }
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
    final single = _single;
    if (single != null) {
      single();
      return;
    }
    _updaters?.notify();
  }

  bool get isDisposed => _disposed;

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
    if (_updaters == null) return _single == null ? 0 : 1;
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
    _single = null;
    _disposed = true;
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

  /// Notifies the listeners of every registered id.
  @protected
  void refreshGroupAll() {
    assert(_debugAssertNotDisposed());
    // Snapshot the groups: a listener may unmount a widget, which calls
    // [disposeId] and would otherwise mutate the map while it is iterated.
    for (final updaters in _updatersGroupIds!.values.toList()) {
      if (!updaters.isDisposed) updaters._notifyUpdate();
    }
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

/// True while the widget tree is being built, where marking an element dirty
/// would throw and the rebuild has to be deferred instead.
///
/// Callers branch on this themselves rather than passing callbacks to a
/// helper: a notification happens once per listener per update, and building
/// the closures for a deferral that almost never happens dominated that path.
bool get isBuildingTree =>
    SchedulerBinding.instance.schedulerPhase ==
    SchedulerPhase.persistentCallbacks;

class Notifier {
  Notifier._();

  static Notifier? _instance;
  static Notifier get instance => _instance ??= Notifier._();

  TrackedBuild? _tracked;

  /// Registers a one-shot disposer for the current build, e.g. the
  /// subscription of [Rx.bindStream]. Dropped before the next build.
  void add(VoidCallback listener) {
    _tracked?.extraDisposers.add(listener);
  }

  /// The last notifier read by the current builder, to skip the lookup when
  /// the same observable is read repeatedly (e.g. iterating an RxList).
  ListNotifierSingleMixin? _lastRead;

  void read(ListNotifierSingleMixin updaters) {
    final tracked = _tracked;
    if (tracked == null || identical(updaters, _lastRead)) return;
    _lastRead = updaters;
    tracked.markRead(updaters);
  }

  T append<T>(TrackedBuild data, T Function() builder) {
    final previous = _tracked;
    final previousRead = _lastRead;
    _tracked = data;
    _lastRead = null;
    data.beginBuild();
    try {
      final result = builder();
      data.endBuild();
      if (data.readNothing && data.throwException) {
        throw const ObxError();
      }
      return result;
    } finally {
      _tracked = previous;
      _lastRead = previousRead;
    }
  }
}

/// The observables a tracked builder (`Obx`, `GetX`) is subscribed to.
///
/// Subscriptions survive rebuilds: each build stamps the observables it read
/// with the current generation, and only the ones missing from the last build
/// are unsubscribed. A builder that keeps reading the same observables — the
/// common case — therefore touches no listener list and allocates nothing,
/// where dropping and recreating every subscription used to cost about 240ns
/// per observable per build.
class TrackedBuild {
  TrackedBuild({required this.updater, this.throwException = true});

  /// Called when any subscribed observable changes.
  final GetStateUpdate updater;

  /// Whether a build that reads no observable at all is an error.
  final bool throwException;

  /// Subscribed observable -> generation it was last read in.
  ///
  /// Identity keyed on purpose: `Rx` overrides `==`/`hashCode` in terms of its
  /// value, and reading that value reports another read, so a normal map would
  /// recurse into [markRead] while looking the key up. Two observables that
  /// happen to hold equal values are also genuinely separate subscriptions.
  final _subscriptions = HashMap<ListNotifierSingleMixin, int>.identity();

  /// Disposers that live for a single build, such as [Rx.bindStream]'s.
  final extraDisposers = <VoidCallback>[];

  int _generation = 0;
  int _readCount = 0;

  void beginBuild() {
    if (extraDisposers.isNotEmpty) {
      for (final disposer in extraDisposers) {
        disposer();
      }
      extraDisposers.clear();
    }
    _generation++;
    _readCount = 0;
  }

  void markRead(ListNotifierSingleMixin notifier) {
    final seen = _subscriptions[notifier];
    if (seen == _generation) return;
    if (seen == null) notifier.addListener(updater);
    _subscriptions[notifier] = _generation;
    _readCount++;
  }

  /// Unsubscribes from the observables that the build just finished did not
  /// read, so a conditional read stops rebuilding on the branch not taken.
  void endBuild() {
    // Every subscription was read again: nothing to drop.
    if (_readCount == _subscriptions.length) return;
    _subscriptions.removeWhere((notifier, seen) {
      if (seen == _generation) return false;
      notifier.removeListener(updater);
      return true;
    });
  }

  /// True when the build read no observable, which is what [ObxError] reports.
  bool get readNothing => _readCount == 0;

  /// How many observables are currently subscribed. For tests.
  @visibleForTesting
  int get subscriptionCount => _subscriptions.length;

  void dispose() {
    for (final notifier in _subscriptions.keys) {
      notifier.removeListener(updater);
    }
    _subscriptions.clear();
    for (final disposer in extraDisposers) {
      disposer();
    }
    extraDisposers.clear();
  }
}

/// Kept for compatibility with code (and benchmarks) written against the
/// previous tracking API, where the per-build state lived in an external
/// [disposers] list. Superseded by [TrackedBuild], which keeps subscriptions
/// across rebuilds; [disposers] now only holds the one-shot disposers.
class NotifyData extends TrackedBuild {
  NotifyData({
    required super.updater,
    required List<VoidCallback> disposers,
    super.throwException,
  }) {
    extraDisposers.addAll(disposers);
  }

  List<VoidCallback> get disposers => extraDisposers;
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
