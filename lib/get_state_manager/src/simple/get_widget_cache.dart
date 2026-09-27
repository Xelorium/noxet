import 'package:flutter/widgets.dart';

abstract class GetWidgetCache extends Widget {
  const GetWidgetCache({super.key});

  @override
  GetWidgetCacheElement createElement() => GetWidgetCacheElement(this);

  @protected
  @factory
  WidgetCache createWidgetCache();
}

class GetWidgetCacheElement extends ComponentElement {
  GetWidgetCacheElement(GetWidgetCache widget)
      : cache = widget.createWidgetCache(),
        super(widget) {
    cache._element = this;
    cache._widget = widget;
  }

  @override
  void mount(Element? parent, dynamic newSlot) {
    cache.onInit();
    super.mount(parent, newSlot);
  }

  @override
  Widget build() => cache.build(this);

  @override
  void update(GetWidgetCache newWidget) {
    final oldWidget = cache._widget!;
    super.update(newWidget);
    cache._widget = newWidget;
    cache.didUpdateWidget(oldWidget);
    rebuild(force: true);
  }

  final WidgetCache<GetWidgetCache> cache;

  @override
  void activate() {
    super.activate();
    markNeedsBuild();
  }

  @override
  void unmount() {
    super.unmount();
    cache.onClose();
    cache._element = null;
  }
}

@optionalTypeArgs
abstract class WidgetCache<T extends GetWidgetCache> {
  T? get widget => _widget;
  T? _widget;

  BuildContext? get context => _element;

  GetWidgetCacheElement? _element;

  @protected
  @mustCallSuper
  void onInit() {}

  @protected
  @mustCallSuper
  void onClose() {}

  /// Called when the element is updated with a new widget instance.
  @protected
  @mustCallSuper
  void didUpdateWidget(covariant T oldWidget) {}

  @protected
  Widget build(BuildContext context);
}
