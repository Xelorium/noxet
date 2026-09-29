import '../simple/get_controllers.dart';
import 'page_state.dart';
import 'page_state_holder.dart';

/// Gives a [GetxController] a page state driven by `update()`, plus any
/// number of independent section states driven by `update([id])`.
///
/// ```dart
/// class ArticlesController extends GetxController
///     with PageStateMixin<List<Article>> {
///   late final comments = section<List<Comment>>('comments');
///
///   @override
///   void onInit() {
///     super.onInit();
///     load(() => api.articles());
///     comments.load(() => api.comments());
///   }
/// }
/// ```
///
/// The page and each section rebuild on their own: reloading `comments` does
/// not flash the whole page.
///
/// ## Do not name a method `refresh`
///
/// `GetxController` already has `refresh()`, and `update()` calls it. Because
/// `void` is a top type in Dart, writing `Future<void> refresh()` on your
/// controller silently *overrides* it instead of being a new method — every
/// state change then re-enters your method and the page loops forever. The
/// same goes for `update()`. Name yours `refreshData()`, `reload()` or
/// similar. [PageStateHolder] throws a [FlutterError] explaining this when it
/// detects the loop, rather than letting the app freeze.
mixin PageStateMixin<T> on GetxController {
  PageStateHolder<T>? _page;
  Map<Object, PageStateHolder<dynamic>>? _sections;

  /// The page's own state. Changing it calls `update()`.
  PageStateHolder<T> get page =>
      _page ??= PageStateHolder<T>(update, () => isClosed);

  /// An independent state identified by [id]. Changing it calls
  /// `update([id])`, so only the `GetBuilder`s with that id rebuild.
  ///
  /// The same [id] always returns the same holder, so it is safe to call from
  /// a getter or a build method. [S] must match the first call for that id.
  PageStateHolder<S> section<S>(Object id) {
    final sections = _sections ??= <Object, PageStateHolder<dynamic>>{};
    final existing = sections[id];
    if (existing != null) return existing as PageStateHolder<S>;
    final created = PageStateHolder<S>(() => update([id]), () => isClosed);
    sections[id] = created;
    return created;
  }

  /// Whether [id] already has a section.
  bool hasSection(Object id) => _sections?.containsKey(id) ?? false;

  // ---- Shortcuts for the page's own state. ----

  PageState<T> get state => page.state;

  /// The loaded value, or null when the page is not in [PageData].
  T? get data => page.data;

  /// See [PageStateHolder.load].
  Future<void> load(
    Future<T> Function() body, {
    bool Function(T value)? isEmpty,
    bool keepDataWhileLoading = false,
    PageState<T>? Function(T value)? mapState,
  }) =>
      page.load(body,
          isEmpty: isEmpty,
          keepDataWhileLoading: keepDataWhileLoading,
          mapState: mapState);

  /// See [PageStateHolder.retry].
  Future<void> retry() => page.retry();

  /// See [PageStateHolder.reset].
  void reset() => page.reset();

  void setState(PageState<T> value) => page.setState(value);

  void setIdle() => page.setIdle();

  void setLoading({double? progress}) => page.setLoading(progress: progress);

  void setEmpty({String? message}) => page.setEmpty(message: message);

  void setData(T value) => page.setData(value);

  void setFailure(Object error, [StackTrace? stackTrace]) =>
      page.setFailure(error, stackTrace);

  void setCustom(PageCustomState<T> value) => page.setCustom(value);

  @override
  void onClose() {
    // Drop in-flight loads so their results cannot touch a closed controller.
    _page?.cancel();
    final sections = _sections;
    if (sections != null) {
      for (final holder in sections.values) {
        holder.cancel();
      }
      sections.clear();
    }
    super.onClose();
  }
}
