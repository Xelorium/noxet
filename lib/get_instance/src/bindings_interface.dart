// ignore: one_member_abstracts
abstract class BindingsInterface<T> {
  T dependencies();
}

/// [Bindings] should be extended or implemented.
/// Groups the registration of dependencies (via Get.put()) in
/// [dependencies].
// ignore: one_member_abstracts
@Deprecated('Use Binding instead')
abstract class Bindings extends BindingsInterface<void> {
  @override
  void dependencies();
}

typedef BindingBuilderCallback = void Function();
