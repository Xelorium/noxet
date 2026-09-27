part of '../rx_types.dart';

class RxMap<K, V> extends GetListenable<Map<K, V>>
    with MapMixin<K, V>, RxObjectMixin<Map<K, V>> {
  /// Wraps [initial] (not a copy). Without [initial], starts with a new
  /// empty map.
  RxMap([Map<K, V>? initial]) : super(initial ?? <K, V>{});

  factory RxMap.from(Map<K, V> other) {
    return RxMap(Map.from(other));
  }

  /// Creates a [LinkedHashMap] with the same keys and values as [other].
  factory RxMap.of(Map<K, V> other) {
    return RxMap(Map.of(other));
  }

  ///Creates an unmodifiable hash based map containing the entries of [other].
  factory RxMap.unmodifiable(Map<dynamic, dynamic> other) {
    return RxMap(Map.unmodifiable(other));
  }

  /// Creates an identity map with the default implementation, [LinkedHashMap].
  factory RxMap.identity() {
    return RxMap(Map.identity());
  }

  @override
  V? operator [](Object? key) {
    return value[key];
  }

  @override
  void operator []=(K key, V value) {
    this.value[key] = value;
    refresh();
  }

  @override
  void clear() {
    value.clear();
    refresh();
  }

  @override
  Iterable<K> get keys => value.keys;

  @override
  V? remove(Object? key) {
    final val = value.remove(key);
    refresh();
    return val;
  }

  // MapMixin implements the operations below on top of `[]=` and `remove`,
  // which would notify once per entry. They are delegated to the underlying
  // map so each call notifies once.

  @override
  void addAll(Map<K, V> other) {
    value.addAll(other);
    refresh();
  }

  @override
  void addEntries(Iterable<MapEntry<K, V>> newEntries) {
    value.addEntries(newEntries);
    refresh();
  }

  @override
  V update(K key, V Function(V value) update, {V Function()? ifAbsent}) {
    final result = value.update(key, update, ifAbsent: ifAbsent);
    refresh();
    return result;
  }

  @override
  void updateAll(V Function(K key, V value) update) {
    value.updateAll(update);
    refresh();
  }

  @override
  void removeWhere(bool Function(K key, V value) test) {
    value.removeWhere(test);
    refresh();
  }

  @override
  bool containsKey(Object? key) => value.containsKey(key);

  @override
  int get length => value.length;

  // @override
  // @protected
  // Map<K, V> get value {
  //   return subject.value;
  //   // RxInterface.proxy?.addListener(subject);
  //   // return _value;
  // }
}

extension MapExtension<K, V> on Map<K, V> {
  RxMap<K, V> get obs {
    return RxMap<K, V>(this);
  }

  void addIf(dynamic condition, K key, V value) {
    if (condition is Condition) condition = condition();
    if (condition is bool && condition) {
      this[key] = value;
    }
  }

  void addAllIf(dynamic condition, Map<K, V> values) {
    if (condition is Condition) condition = condition();
    if (condition is bool && condition) addAll(values);
  }

  void assign(K key, V val) {
    if (this is RxMap) {
      final map = (this as RxMap);
      // map._value;
      map.value.clear();
      this[key] = val;
    } else {
      clear();
      this[key] = val;
    }
  }

  void assignAll(Map<K, V> val) {
    if (val is RxMap && this is RxMap) {
      if ((val as RxMap).value == (this as RxMap).value) return;
    }
    if (this is RxMap) {
      final map = (this as RxMap);
      if (map.value == val) return;
      final newEntries = Map<K, V>.of(val);
      map.value.clear();
      addAll(newEntries);
    } else {
      if (this == val) return;
      clear();
      addAll(val);
    }
  }
}
