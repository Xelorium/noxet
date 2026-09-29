import 'dart:async';

import 'package:flutter/foundation.dart';

import 'page_state.dart';

/// True for the values that usually mean "there is nothing to show": null,
/// an empty collection, or a blank string.
///
/// Mirrors what `StateMixin.futurize` treats as empty in
/// `rx_flutter/rx_notifier.dart`; that helper is private there, and this
/// module keeps its own copy rather than reopening tested code.
bool isEmptyValue(Object? value) {
  if (value == null) return true;
  if (value is Iterable) return value.isEmpty;
  if (value is Map) return value.isEmpty;
  if (value is String) return value.trim().isEmpty;
  return false;
}

/// Holds one [PageState] and notifies its owner when it changes.
///
/// A controller has one of these for the page itself and one per section, so
/// the page and each section move independently. Created by
/// `PageStateMixin.page` and `PageStateMixin.section`, not directly.
class PageStateHolder<T> {
  /// Created by `PageStateMixin`, not directly: the first callback rebuilds
  /// the bound widgets, the second reports the controller's lifecycle.
  PageStateHolder(this._notify, this._isClosed);

  /// Rebuilds what is bound to this holder: `update()` for a page,
  /// `update([id])` for a section.
  final void Function() _notify;

  /// The owning controller's `isClosed`, so a late result cannot touch a
  /// disposed page.
  final bool Function() _isClosed;

  PageState<T> _state = PageIdle<T>();

  /// How deep we are inside [_notify]. A listener may legitimately set the
  /// state again, but an unbounded chain means something is looping.
  int _depth = 0;

  /// Past this, a chain of notifications is a bug rather than a nested
  /// update. Deep enough that ordinary re-entrancy never reaches it.
  static const _maxDepth = 20;

  /// Bumped by every [load] and [reset], so a result that arrives after a
  /// newer call started is dropped instead of overwriting it.
  int _token = 0;

  Future<T> Function()? _lastBody;
  bool Function(T value)? _lastIsEmpty;
  PageState<T>? Function(T value)? _lastMapState;
  bool _lastKeepData = false;

  PageState<T> get state => _state;

  /// The loaded value, or null when the state is not [PageData].
  T? get data => _state.valueOrNull;

  bool get isIdle => _state.isIdle;

  bool get isLoading => _state.isLoading;

  bool get isEmpty => _state.isEmpty;

  bool get isFailure => _state.isFailure;

  bool get isData => _state.isData;

  /// Replaces the state and rebuilds the widgets bound to this holder.
  ///
  /// Does nothing once the controller is closed, so a late callback cannot
  /// resurrect a disposed page.
  void setState(PageState<T> value) {
    if (_isClosed()) return;
    _state = value;

    if (_depth >= _maxDepth) {
      // Almost always a method on the controller that shadows one of
      // GetxController's own. `refresh()` is the usual culprit: `void` is a
      // top type in Dart, so `Future<void> refresh()` silently overrides
      // `ListNotifier.refresh()`, and since `update()` calls `refresh()`,
      // every state change re-enters the override.
      throw FlutterError(
        'PageStateHolder kept notifying $_maxDepth levels deep.\n'
        'A notification is triggering another state change without end. '
        'Check the controller for methods that shadow GetxController\'s '
        'own: refresh(), update(), onInit(), onClose(). Renaming '
        'refresh() to something like refreshData() is the usual fix.',
      );
    }

    _depth++;
    try {
      _notify();
    } finally {
      _depth--;
    }
  }

  void setIdle() => setState(PageIdle<T>());

  void setLoading({double? progress}) =>
      setState(PageLoading<T>(progress: progress));

  void setEmpty({String? message}) => setState(PageEmpty<T>(message: message));

  void setData(T value) => setState(PageData<T>(value));

  void setFailure(Object error, [StackTrace? stackTrace]) =>
      setState(PageFailure<T>(error, stackTrace));

  void setCustom(PageCustomState<T> value) => setState(value);

  /// Runs [body], moving through [PageLoading] to [PageData], [PageEmpty] or
  /// [PageFailure].
  ///
  /// - Calling it again while one is in flight cancels the older result: only
  ///   the newest call can change the state.
  /// - [isEmpty] decides what counts as empty; by default null, an empty
  ///   collection and a blank string do. Pass `(_) => false` to always land
  ///   on [PageData].
  /// - [keepDataWhileLoading] leaves the current [PageData] in place instead
  ///   of showing a spinner, which is what a pull-to-refresh wants.
  /// - [mapState] turns the result into a state of your own, for the cases a
  ///   load does not end in plain data:
  ///
  ///   ```dart
  ///   load(
  ///     () => api.articles(),
  ///     mapState: (result) =>
  ///         result.isPaywalled ? Paywalled(result.remaining) : null,
  ///   );
  ///   ```
  ///
  ///   Returning null falls back to the usual data/empty decision.
  ///
  /// Errors thrown synchronously by [body] are caught too. The returned
  /// future completes when the state has been applied and never throws.
  Future<void> load(
    Future<T> Function() body, {
    bool Function(T value)? isEmpty,
    bool keepDataWhileLoading = false,
    PageState<T>? Function(T value)? mapState,
  }) async {
    if (_isClosed()) return;

    _lastBody = body;
    _lastIsEmpty = isEmpty;
    _lastMapState = mapState;
    _lastKeepData = keepDataWhileLoading;

    final token = ++_token;
    if (!keepDataWhileLoading || !_state.isData) {
      setLoading();
    }

    try {
      final value = await Future<T>.sync(body);
      if (token != _token || _isClosed()) return;
      final mapped = mapState?.call(value);
      if (mapped != null) {
        setState(mapped);
        return;
      }
      final empty = isEmpty?.call(value) ?? isEmptyValue(value);
      setState(empty ? PageEmpty<T>() : PageData<T>(value));
    } catch (error, stackTrace) {
      if (token != _token || _isClosed()) return;
      setState(PageFailure<T>(error, stackTrace));
    }
  }

  /// Runs the last [load] again, for a retry button. Does nothing when
  /// nothing has been loaded yet.
  Future<void> retry() {
    final body = _lastBody;
    if (body == null) return Future<void>.value();
    return load(
      body,
      isEmpty: _lastIsEmpty,
      keepDataWhileLoading: _lastKeepData,
      mapState: _lastMapState,
    );
  }

  /// Back to [PageIdle], dropping any in-flight load.
  void reset() {
    _token++;
    _lastBody = null;
    _lastIsEmpty = null;
    _lastMapState = null;
    _lastKeepData = false;
    setIdle();
  }

  /// Drops an in-flight load without touching the state. Called when the
  /// controller closes.
  void cancel() {
    _token++;
  }

  @override
  String toString() => 'PageStateHolder<$T>($_state)';
}
