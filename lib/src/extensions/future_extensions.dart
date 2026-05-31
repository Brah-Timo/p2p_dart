/// Future utility extensions.
library;

import 'dart:async';

/// Convenience extensions on [Future].
extension P2PFutureExtensions<T> on Future<T> {
  /// Returns `null` instead of throwing on timeout.
  Future<T?> orNullOnTimeout(Duration duration) async {
    try {
      return await timeout(duration);
    } on TimeoutException {
      return null;
    }
  }

  /// Returns [fallback] if this future throws.
  Future<T> orElse(T fallback) async {
    try {
      return await this;
    } catch (_) {
      return fallback;
    }
  }

  /// Executes [onSuccess] when resolved, [onFailure] on error.
  Future<T> tap({
    void Function(T value)? onSuccess,
    void Function(Object error)? onFailure,
  }) {
    return then(
      (value) {
        onSuccess?.call(value);
        return value;
      },
      onError: (Object e, StackTrace s) {
        onFailure?.call(e);
        throw e;
      },
    );
  }

  /// Logs and re-throws errors without consuming them.
  Future<T> logError(void Function(Object error) logger) {
    return catchError((Object e) {
      logger(e);
      throw e;
    });
  }

  /// Times this future and calls [onComplete] with the elapsed duration.
  Future<T> timed(void Function(Duration elapsed) onComplete) async {
    final start = DateTime.now();
    try {
      final result = await this;
      onComplete(DateTime.now().difference(start));
      return result;
    } catch (_) {
      onComplete(DateTime.now().difference(start));
      rethrow;
    }
  }
}

/// Extensions on [Future<void>].
extension P2PFutureVoidExtensions on Future<void> {
  /// Silently ignores any error.
  Future<void> ignoreErrors() async {
    try {
      await this;
    } catch (_) {}
  }
}
