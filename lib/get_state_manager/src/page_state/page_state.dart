/// The state a page (or a section of one) can be in.
///
/// The hierarchy is sealed, so a `switch` over it is exhaustive and the
/// compiler tells you when a branch is missing:
///
/// ```dart
/// switch (controller.state) {
///   PageIdle() || PageEmpty() => const EmptyView(),
///   PageLoading() => const Spinner(),
///   PageData(:final value) => ArticleList(value),
///   PageFailure(:final error) => ErrorView(error),
///   PageCustomState() => const SizedBox.shrink(),
/// }
/// ```
///
/// [PageCustomState] is the extension point: it is `base` rather than `final`,
/// so your own states can extend it from outside this package while the
/// switch above stays exhaustive.
sealed class PageState<T> {
  const PageState();
}

/// Nothing has been asked for yet. The state a holder starts in.
final class PageIdle<T> extends PageState<T> {
  const PageIdle();

  @override
  String toString() => 'PageIdle<$T>()';
}

/// Work is in progress. [progress] is optional, for determinate indicators.
final class PageLoading<T> extends PageState<T> {
  const PageLoading({this.progress});

  final double? progress;

  @override
  String toString() => 'PageLoading<$T>(progress: $progress)';
}

/// The work finished but there is nothing to show.
final class PageEmpty<T> extends PageState<T> {
  const PageEmpty({this.message});

  final String? message;

  @override
  String toString() => 'PageEmpty<$T>(message: $message)';
}

/// The work failed. [stackTrace] is kept so the page can report it.
final class PageFailure<T> extends PageState<T> {
  const PageFailure(this.error, [this.stackTrace]);

  final Object error;
  final StackTrace? stackTrace;

  @override
  String toString() => 'PageFailure<$T>($error)';
}

/// The work succeeded and produced [value].
final class PageData<T> extends PageState<T> {
  const PageData(this.value);

  final T value;

  @override
  String toString() => 'PageData<$T>($value)';
}

/// Extend this to add states of your own, for example a paywall or a
/// "location permission denied" screen:
///
/// ```dart
/// final class Paywalled extends PageCustomState<List<Article>> {
///   const Paywalled(this.remaining);
///   final int remaining;
/// }
/// ```
///
/// When matching, put your own type *before* the `PageCustomState()` branch,
/// otherwise the broader one wins:
///
/// ```dart
/// switch (state) {
///   Paywalled(:final remaining) => Paywall(remaining),
///   PageCustomState() => const SizedBox.shrink(),
///   // ...
/// }
/// ```
abstract base class PageCustomState<T> extends PageState<T> {
  const PageCustomState();
}

/// Reading a [PageState] without a `switch`, for the cases where one branch
/// is all you care about.
extension PageStateX<T> on PageState<T> {
  bool get isIdle => this is PageIdle<T>;

  bool get isLoading => this is PageLoading<T>;

  bool get isEmpty => this is PageEmpty<T>;

  bool get isFailure => this is PageFailure<T>;

  bool get isData => this is PageData<T>;

  bool get isCustom => this is PageCustomState<T>;

  /// The value when this is [PageData], null otherwise.
  T? get valueOrNull {
    final self = this;
    return self is PageData<T> ? self.value : null;
  }

  /// The error when this is [PageFailure], null otherwise.
  Object? get errorOrNull {
    final self = this;
    return self is PageFailure<T> ? self.error : null;
  }
}
