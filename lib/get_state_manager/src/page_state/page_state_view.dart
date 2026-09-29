import 'package:flutter/material.dart';

import '../simple/get_controllers.dart';
import '../simple/get_state.dart';
import 'page_state.dart';
import 'page_state_holder.dart';
import 'page_state_mixin.dart';

/// Builds the widget for a state that carries no value.
typedef PageStateWidgetBuilder<T> = Widget Function(
    BuildContext context, PageState<T> state);

/// Builds the widget for [PageData].
typedef PageDataWidgetBuilder<T> = Widget Function(
    BuildContext context, T value);

/// App-wide fallbacks for the branches a page does not spell out.
///
/// Wrap the app once and every [PageStateView] and [PageSectionView] below it
/// picks these up:
///
/// ```dart
/// PageStateDefaults(
///   loading: (context, state) => const MySpinner(),
///   failure: (context, state) => MyError(state.errorOrNull),
///   child: MaterialApp(...),
/// )
/// ```
class PageStateDefaults extends InheritedWidget {
  const PageStateDefaults({
    super.key,
    required super.child,
    this.idle,
    this.loading,
    this.empty,
    this.failure,
    this.custom,
  });

  final PageStateWidgetBuilder<dynamic>? idle;
  final PageStateWidgetBuilder<dynamic>? loading;
  final PageStateWidgetBuilder<dynamic>? empty;
  final PageStateWidgetBuilder<dynamic>? failure;
  final PageStateWidgetBuilder<dynamic>? custom;

  static PageStateDefaults? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PageStateDefaults>();

  @override
  bool updateShouldNotify(PageStateDefaults oldWidget) =>
      idle != oldWidget.idle ||
      loading != oldWidget.loading ||
      empty != oldWidget.empty ||
      failure != oldWidget.failure ||
      custom != oldWidget.custom;
}

/// Picks the widget for [state], falling back to [PageStateDefaults] and then
/// to a plain built-in.
Widget buildPageState<T>(
  BuildContext context,
  PageState<T> state, {
  required PageDataWidgetBuilder<T> onData,
  PageStateWidgetBuilder<T>? onIdle,
  PageStateWidgetBuilder<T>? onLoading,
  PageStateWidgetBuilder<T>? onEmpty,
  PageStateWidgetBuilder<T>? onFailure,
  PageStateWidgetBuilder<T>? onCustom,
}) {
  final defaults = PageStateDefaults.maybeOf(context);

  Widget fallback(
    PageStateWidgetBuilder<T>? given,
    PageStateWidgetBuilder<dynamic>? shared,
    Widget Function() last,
  ) {
    if (given != null) return given(context, state);
    if (shared != null) return shared(context, state);
    return last();
  }

  return switch (state) {
    PageData(:final value) => onData(context, value),
    PageLoading() => fallback(onLoading, defaults?.loading,
        () => const Center(child: CircularProgressIndicator())),
    PageEmpty(:final message) => fallback(
        onEmpty,
        defaults?.empty,
        () => message == null
            ? const SizedBox.shrink()
            : Center(child: Text(message))),
    PageFailure(:final error) => fallback(onFailure, defaults?.failure,
        () => Center(child: Text('$error'))),
    PageIdle() =>
      fallback(onIdle, defaults?.idle, () => const SizedBox.shrink()),
    PageCustomState() => fallback(
        onCustom, defaults?.custom, () => const SizedBox.shrink()),
  };
}

/// Binds a controller's page state to widgets, using `GetBuilder` (not `Obx`).
///
/// ```dart
/// PageStateView<ArticlesController, List<Article>>(
///   init: ArticlesController(),
///   onData: (context, articles) => ArticleList(articles),
///   onEmpty: (context, state) => const Text('Nothing here yet'),
/// )
/// ```
///
/// Only [onData] is required; the rest fall back to [PageStateDefaults] and
/// then to built-ins. To match your own [PageCustomState] types, switch on
/// `state` inside [onCustom].
class PageStateView<C extends PageStateMixin<T>, T> extends StatelessWidget {
  const PageStateView({
    super.key,
    required this.onData,
    this.init,
    this.tag,
    this.global = true,
    this.autoRemove = true,
    this.onIdle,
    this.onLoading,
    this.onEmpty,
    this.onFailure,
    this.onCustom,
  });

  /// Creates the controller when it is not registered yet, like
  /// `GetBuilder(init:)`.
  final C? init;
  final String? tag;
  final bool global;
  final bool autoRemove;

  final PageDataWidgetBuilder<T> onData;
  final PageStateWidgetBuilder<T>? onIdle;
  final PageStateWidgetBuilder<T>? onLoading;
  final PageStateWidgetBuilder<T>? onEmpty;
  final PageStateWidgetBuilder<T>? onFailure;
  final PageStateWidgetBuilder<T>? onCustom;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<C>(
      init: init,
      tag: tag,
      global: global,
      autoRemove: autoRemove,
      builder: (controller) => buildPageState<T>(
        context,
        controller.state,
        onData: onData,
        onIdle: onIdle,
        onLoading: onLoading,
        onEmpty: onEmpty,
        onFailure: onFailure,
        onCustom: onCustom,
      ),
    );
  }
}

/// Binds one section of a controller, identified by [id], so it rebuilds on
/// `update([id])` alone.
///
/// ```dart
/// PageSectionView<ArticlesController, List<Comment>>(
///   id: 'comments',
///   select: (controller) => controller.comments,
///   onData: (context, comments) => CommentList(comments),
/// )
/// ```
class PageSectionView<C extends GetxController, S> extends StatelessWidget {
  const PageSectionView({
    super.key,
    required this.id,
    required this.select,
    required this.onData,
    this.tag,
    this.global = true,
    this.autoRemove = true,
    this.onIdle,
    this.onLoading,
    this.onEmpty,
    this.onFailure,
    this.onCustom,
  });

  /// The id passed to `update([id])`, and to `GetBuilder(id:)`.
  final Object id;

  /// Returns the holder to render, e.g. `(c) => c.comments`.
  final PageStateHolder<S> Function(C controller) select;

  final String? tag;
  final bool global;
  final bool autoRemove;

  final PageDataWidgetBuilder<S> onData;
  final PageStateWidgetBuilder<S>? onIdle;
  final PageStateWidgetBuilder<S>? onLoading;
  final PageStateWidgetBuilder<S>? onEmpty;
  final PageStateWidgetBuilder<S>? onFailure;
  final PageStateWidgetBuilder<S>? onCustom;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<C>(
      id: id,
      tag: tag,
      global: global,
      autoRemove: autoRemove,
      builder: (controller) => buildPageState<S>(
        context,
        select(controller).state,
        onData: onData,
        onIdle: onIdle,
        onLoading: onLoading,
        onEmpty: onEmpty,
        onFailure: onFailure,
        onCustom: onCustom,
      ),
    );
  }
}
