import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../get_core/get_core.dart';
import 'lifecycle.dart';

/// Key of a registration: the requested type plus the optional tag.
///
/// Records have structural equality, so this is used directly as the map key
/// instead of building a `'Type#tag'` string on every lookup.
typedef _InstKey = (Type, String?);

class InstanceInfo {
  final bool? isPermanent;
  final bool? isSingleton;
  bool get isCreate => !isSingleton!;
  final bool isRegistered;
  final bool isPrepared;
  final bool? isInit;
  const InstanceInfo({
    required this.isPermanent,
    required this.isSingleton,
    required this.isRegistered,
    required this.isPrepared,
    required this.isInit,
  });

  @override
  String toString() {
    return 'InstanceInfo(isPermanent: $isPermanent, isSingleton: $isSingleton, isRegistered: $isRegistered, isPrepared: $isPrepared, isInit: $isInit)';
  }
}

extension ResetInstance on GetInterface {
  /// Clears all registered instances (and/or tags).
  /// Even the persistent ones.
  /// This should be used at the end or tearDown of unit tests.
  ///
  /// [clearRouteBindings] is kept for API compatibility and has no effect.
  /// Every initialized instance is closed (`onDelete()`) before being
  /// removed, including permanent instances and services.
  bool resetInstance(
      {@Deprecated('Has no effect without route management')
      bool clearRouteBindings = true}) {
    deleteAll(force: true);
    Inst._singl.clear();

    return true;
  }
}

extension Inst on GetInterface {
  T call<T>() => find<T>();

  /// Holds references to every registered Instance when using
  /// `Get.put()`
  static final Map<_InstKey, _InstanceBuilderFactory> _singl = {};

  /// Holds a reference to every registered callback when using
  /// `Get.lazyPut()`
  // static final Map<String, _Lazy> _factory = {};

  // void injector<S>(
  //   InjectorBuilderCallback<S> fn, {
  //   String? tag,
  //   bool fenix = false,
  //   //  bool permanent = false,
  // }) {
  //   lazyPut(
  //     () => fn(this),
  //     tag: tag,
  //     fenix: fenix,
  //     // permanent: permanent,
  //   );
  // }

  S put<S>(
    S dependency, {
    String? tag,
    bool permanent = false,
  }) {
    _insert(
        isSingleton: true,
        name: tag,
        permanent: permanent,
        warnIfRegistered: true,
        builder: (() => dependency));
    return find<S>(tag: tag);
  }

  /// Creates a new Instance<S> lazily from the `<S>builder()` callback.
  ///
  /// The first time you call `Get.find()`, the `builder()` callback will create
  /// the Instance and persisted as a Singleton (like you would
  /// use `Get.put()`).
  ///
  /// Using `Get.smartManagement` as [SmartManagement.keepFactory] has
  /// the same outcome as using `fenix:true` :
  /// The internal register of `builder()` will remain in memory to recreate
  /// the Instance if the Instance has been removed with `Get.delete()`.
  /// Therefore, future calls to `Get.find()` will return the same Instance.
  ///
  /// If you need to make use of GetxController's life-cycle
  /// (`onInit(), onStart(), onClose()`) [fenix] is a great choice to mix with
  /// `GetBuilder()` and `GetX()` widgets.
  ///
  /// Subsequent calls to `Get.lazyPut()` with the same parameters
  /// (<[S]> and optionally [tag] will **not** override the original).
  void lazyPut<S>(
    InstanceBuilderCallback<S> builder, {
    String? tag,
    bool? fenix,
    bool permanent = false,
  }) {
    _insert(
      isSingleton: true,
      name: tag,
      permanent: permanent,
      builder: builder,
      fenix: fenix ?? Get.smartManagement == SmartManagement.keepFactory,
    );
  }

  /// Creates a new Class Instance [S] from the builder callback[S].
  /// Every time [find]<[S]>() is used, it calls the builder method to generate
  /// a new Instance [S].
  /// It also registers each `instance.onClose()` with the current
  /// Route `Get.reference` to keep the lifecycle active.
  /// Is important to know that the instances created are only stored per Route.
  /// So, if you call `Get.delete<T>()` the "instance factory" used in this
  /// method (`Get.spawn<T>()`) will be removed, but NOT the instances
  /// already created by it.
  ///
  /// Example:
  ///
  /// ```Get.spawn(() => Repl());
  /// Repl a = find();
  /// Repl b = find();
  /// print(a==b); (false)```
  void spawn<S>(
    InstanceBuilderCallback<S> builder, {
    String? tag,
    bool permanent = true,
  }) {
    _insert(
      isSingleton: false,
      name: tag,
      builder: builder,
      permanent: permanent,
    );
  }

  /// Injects the Instance [S] builder into the `_singleton` HashMap.
  void _insert<S>({
    bool? isSingleton,
    String? name,
    bool permanent = false,
    required InstanceBuilderCallback<S> builder,
    bool fenix = false,
    bool warnIfRegistered = false,
  }) {
    final key = (S, name);

    final previous = _singl[key];
    if (previous != null && !previous.isDirty) {
      if (warnIfRegistered && kDebugMode) {
        Get.log(
          // ignore: lines_longer_than_80_chars
          '"${_keyLabel(key)}" is already registered; the existing instance is kept and the new one is discarded (it is never initialized nor closed). Use Get.replace() to swap it, or Get.delete() first.',
          isError: true,
        );
      }
      return;
    }

    _singl[key] = _InstanceBuilderFactory<S>(
      isSingleton: isSingleton,
      builderFunc: builder,
      permanent: permanent,
      isInit: false,
      fenix: fenix,
      tag: name,
    );

    // A dirty registration is replaced; close the instance it held.
    final previousInstance = previous?.dependency;
    if (previousInstance is GetLifeCycleMixin) {
      previousInstance.onDelete();
      if (Get.isLogEnable) Get.log('"${_keyLabel(key)}" onDelete() called');
    }
  }

  /// Initializes the dependencies for a Class Instance [S] (or tag),
  /// If its a Controller, it starts the lifecycle process.
  /// Optionally associating the current Route to the lifetime of the instance,
  /// if `Get.smartManagement` is marked as [SmartManagement.full] or
  /// [SmartManagement.keepFactory]
  /// Only flags `isInit` if it's using `Get.create()`
  /// (not for Singletons access).
  /// Returns the instance if not initialized, required for Get.create() to
  /// work properly.
  S? _initDependencies<S>(_InstanceBuilderFactory dep, {String? name}) {
    if (dep.isInit) return null;
    final isSingleton = dep.isSingleton ?? false;
    // Flag before starting so a `find` from inside `onInit` does not start
    // the instance twice.
    if (isSingleton) dep.isInit = true;
    try {
      return _startController<S>(dep, tag: name);
    } catch (_) {
      if (isSingleton) {
        dep.isInit = false;
        dep.dependency = null;
      }
      rethrow;
    }
  }

  InstanceInfo getInstanceInfo<S>({String? tag}) {
    final build = _singl[(S, tag)];

    return InstanceInfo(
      isPermanent: build?.permanent,
      isSingleton: build?.isSingleton,
      isRegistered: build != null,
      isPrepared: !(build?.isInit ?? true),
      isInit: build?.isInit,
    );
  }

  /// Marks the instance as replaceable: the next `put`/`lazyPut`/`spawn` of
  /// the same type (and tag) replaces this registration and closes the
  /// instance it held, instead of being ignored.
  void markAsDirty<S>({String? tag, String? key}) {
    final instKey = key != null ? _resolveLegacyKey(key) : (S, tag);
    final dep = instKey == null ? null : _singl[instKey];
    if (dep != null && !dep.permanent) {
      dep.isDirty = true;
    }
  }

  /// Initializes the controller
  S _startController<S>(_InstanceBuilderFactory dep, {String? tag}) {
    final i = dep.getDependency() as S;
    if (i is GetLifeCycleMixin) {
      i.onStart();
      // Guarded: building these strings means a Type.toString() on every
      // instantiation, which showed up in the page-open benchmark.
      if (Get.isLogEnable) {
        if (tag == null) {
          Get.log('Instance "$S" has been initialized');
        } else {
          Get.log('Instance "$S" with tag "$tag" has been initialized');
        }
      }
    }
    return i;
  }

  S putOrFind<S>(InstanceBuilderCallback<S> dep, {String? tag}) {
    if (isRegistered<S>(tag: tag)) return find<S>(tag: tag);
    return put(dep(), tag: tag);
  }

  /// Finds the registered type <[S]> (or [tag])
  /// In case of using Get.[create] to register a type <[S]> or [tag],
  /// it will create an instance each time you call [find].
  /// If the registered type <[S]> (or [tag]) is a Controller,
  /// it will initialize it's lifecycle.
  ///
  /// Throws a [GetInstanceNotFoundError] if nothing is registered for <[S]>
  /// (and [tag]).
  S find<S>({String? tag}) {
    // One map lookup: the record key needs no string to be built, and the
    // registration is passed down instead of being looked up again.
    final dep = _singl[(S, tag)];
    if (dep == null) {
      throw GetInstanceNotFoundError(type: S, tag: tag);
    }

    /// although dirty solution, the lifecycle starts inside
    /// `initDependencies`, so we have to return the instance from there
    /// to make it compatible with `Get.create()`.
    final i = _initDependencies<S>(dep, name: tag);
    return i ?? dep.getDependency() as S;
  }

  /// The findOrNull method will return the instance if it is registered;
  /// otherwise, it will return null.
  S? findOrNull<S>({String? tag}) {
    if (_singl.containsKey((S, tag))) {
      return find<S>(tag: tag);
    }
    return null;
  }

  /// Replace a parent instance of a class in dependency management
  /// with a [child] instance
  /// - [tag] optional, if you use a [tag] to register the Instance.
  void replace<P>(P child, {String? tag}) {
    final info = getInstanceInfo<P>(tag: tag);
    final permanent = (info.isPermanent ?? false);
    delete<P>(tag: tag, force: permanent);
    put(child, tag: tag, permanent: permanent);
  }

  /// Replaces a parent instance with a new Instance<P> lazily from the
  /// `<P>builder()` callback.
  /// - [tag] optional, if you use a [tag] to register the Instance.
  /// - [fenix] optional
  ///
  ///  Note: if fenix is not provided it will be set to true if
  /// the parent instance was permanent
  void lazyReplace<P>(InstanceBuilderCallback<P> builder,
      {String? tag, bool? fenix}) {
    final info = getInstanceInfo<P>(tag: tag);
    final permanent = (info.isPermanent ?? false);
    delete<P>(tag: tag, force: permanent);
    lazyPut(builder, tag: tag, fenix: fenix ?? permanent);
  }

  /// The textual form of a registration key, used in logs and by the legacy
  /// `key:` parameter of [delete] / [reload] / [markAsDirty].
  /// `#` never appears in a type name, so `Foo` + tag `Bar` and `FooBar`
  /// get different keys.
  static String _stringKey(Type type, String? name) =>
      name == null ? type.toString() : '$type#$name';

  static String _keyLabel(_InstKey key) => _stringKey(key.$1, key.$2);

  /// Resolves a `'Type#tag'` string back to its registration key.
  ///
  /// Only used by the `key:` parameter of [delete] / [reload] /
  /// [markAsDirty], documented as internal; the scan is over the
  /// registrations, and the hot paths ([find], [isRegistered]) never take it.
  static _InstKey? _resolveLegacyKey(String key) {
    for (final candidate in _singl.keys) {
      if (_keyLabel(candidate) == key) return candidate;
    }
    return null;
  }

  /// Delete registered Class Instance [S] (or [tag]) and, closes any open
  /// controllers `DisposableInterface`, cleans up the memory
  ///
  /// /// Deletes the Instance<[S]>, cleaning the memory.
  //  ///
  //  /// - [tag] Optional "tag" used to register the Instance
  //  /// - [key] For internal usage, is the processed key used to register
  //  ///   the Instance. **don't use** it unless you know what you are doing.

  /// Deletes the Instance<[S]>, cleaning the memory and closes any open
  /// controllers (`DisposableInterface`).
  ///
  /// - [tag] Optional "tag" used to register the Instance
  /// - [key] For internal usage, is the processed key used to register
  ///   the Instance. **don't use** it unless you know what you are doing.
  /// - [force] Will delete an Instance even if marked as `permanent`.
  bool delete<S>({String? tag, String? key, bool force = false}) {
    final instKey = key != null ? _resolveLegacyKey(key) : (S, tag);
    final builder = instKey == null ? null : _singl[instKey];

    if (builder == null) {
      Get.log('Instance "${key ?? _stringKey(S, tag)}" already removed.',
          isError: true);
      return false;
    }

    return _delete(instKey!, builder, force: force);
  }

  bool _delete(_InstKey key, _InstanceBuilderFactory builder,
      {bool force = false}) {
    if (builder.permanent && !force) {
      Get.log(
        // ignore: lines_longer_than_80_chars
        '"${_keyLabel(key)}" has been marked as permanent, SmartManagement is not authorized to delete it.',
        isError: true,
      );
      return false;
    }
    final i = builder.dependency;

    if (i is GetxServiceMixin && !force) {
      return false;
    }

    if (i is GetLifeCycleMixin) {
      i.onDelete();
      if (Get.isLogEnable) Get.log('"${_keyLabel(key)}" onDelete() called');
    }

    if (builder.fenix) {
      builder.dependency = null;
      builder.isInit = false;
    } else {
      _singl.remove(key);
    }
    if (Get.isLogEnable) Get.log('"${_keyLabel(key)}" deleted from memory');
    return true;
  }

  /// Delete all registered Class Instances and, closes any open
  /// controllers `DisposableInterface`, cleans up the memory
  ///
  /// - [force] Will delete the Instances even if marked as `permanent`.
  void deleteAll({bool force = false}) {
    for (final entry in _singl.entries.toList()) {
      _delete(entry.key, entry.value, force: force);
    }
  }

  /// Closes every instance (see [reload]) so it is recreated by its builder
  /// on the next [find].
  void reloadAll({bool force = false}) {
    for (final entry in _singl.entries.toList()) {
      _reload(entry.key, entry.value, force: force);
    }
  }

  void reload<S>({
    String? tag,
    String? key,
    bool force = false,
  }) {
    final instKey = key != null ? _resolveLegacyKey(key) : (S, tag);
    final builder = instKey == null ? null : _singl[instKey];
    if (builder == null) {
      Get.log('Instance "${key ?? _stringKey(S, tag)}" is not registered.',
          isError: true);
      return;
    }

    _reload(instKey!, builder, force: force);
  }

  void _reload(_InstKey key, _InstanceBuilderFactory builder,
      {bool force = false}) {
    if (builder.permanent && !force) {
      Get.log(
        '''Instance "${_keyLabel(key)}" is permanent. Use [force = true] to force the restart.''',
        isError: true,
      );
      return;
    }

    final i = builder.dependency;

    if (i is GetxServiceMixin && !force) {
      return;
    }

    if (i is GetLifeCycleMixin) {
      i.onDelete();
      if (Get.isLogEnable) Get.log('"${_keyLabel(key)}" onDelete() called');
    }

    builder.dependency = null;
    builder.isInit = false;
    if (Get.isLogEnable) Get.log('Instance "${_keyLabel(key)}" was restarted.');
  }

  /// Check if a Class Instance<[S]> (or [tag]) is registered in memory.
  /// - [tag] is optional, if you used a [tag] to register the Instance.
  bool isRegistered<S>({String? tag}) => _singl.containsKey((S, tag));

  /// Checks if a lazy factory callback `Get.lazyPut()` that returns an
  /// Instance<[S]> is registered in memory.
  /// - [tag] is optional, if you used a [tag] to register the lazy Instance.
  bool isPrepared<S>({String? tag}) {
    final builder = _singl[(S, tag)];
    return builder != null && !builder.isInit;
  }
}

/// Thrown by [Inst.find] when the requested type (optionally with a [tag])
/// has not been registered with `Get.put()`, `Get.lazyPut()` or `Get.spawn()`.
///
/// Being an [Error], it carries the [stackTrace] of the failed lookup.
class GetInstanceNotFoundError extends Error {
  GetInstanceNotFoundError({required this.type, this.tag});

  /// The type that was looked up.
  final Type type;

  /// The tag it was looked up with, if any.
  final String? tag;

  @override
  String toString() {
    final target = tag == null ? '"$type"' : '"$type" with tag "$tag"';
    final tagArg = tag == null ? '' : ', tag: "$tag"';
    return '[Get] $target is not registered. '
        'Call "Get.put($type()$tagArg)" or '
        '"Get.lazyPut(() => $type()$tagArg)" before using it.';
  }
}

typedef InstanceBuilderCallback<S> = S Function();

typedef InstanceCreateBuilderCallback<S> = S Function(BuildContext _);

// typedef InstanceBuilderCallback<S> = S Function();

// typedef InjectorBuilderCallback<S> = S Function(Inst);

typedef AsyncInstanceBuilderCallback<S> = Future<S> Function();

/// Internal class to register instances with `Get.put<S>()`.
class _InstanceBuilderFactory<S> {
  /// Marks the Builder as a single instance.
  /// For reusing [dependency] instead of [builderFunc]
  bool? isSingleton;

  /// When fenix mode is available, when a new instance is need
  /// Instance manager will recreate a new instance of S
  bool fenix;

  /// Stores the actual object instance when [isSingleton]=true.
  S? dependency;

  /// Generates (and regenerates) the instance when [isSingleton]=false.
  /// Usually used by factory methods
  InstanceBuilderCallback<S> builderFunc;

  /// Flag to persist the instance in memory,
  /// without considering `Get.smartManagement`
  bool permanent = false;

  bool isInit = false;

  bool isDirty = false;

  String? tag;

  _InstanceBuilderFactory({
    required this.isSingleton,
    required this.builderFunc,
    required this.permanent,
    required this.isInit,
    required this.fenix,
    required this.tag,
  });

  void _showInitLog() {
    if (!Get.isLogEnable) return;
    if (tag == null) {
      Get.log('Instance "$S" has been created');
    } else {
      Get.log('Instance "$S" has been created with tag "$tag"');
    }
  }

  /// Gets the actual instance by it's [builderFunc] or the persisted instance.
  S getDependency() {
    if (isSingleton!) {
      if (dependency == null) {
        _showInitLog();
        dependency = builderFunc();
      }
      return dependency!;
    } else {
      return builderFunc();
    }
  }
}
