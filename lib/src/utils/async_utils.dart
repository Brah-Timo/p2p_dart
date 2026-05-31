/// Asynchronous utility helpers.
library;

import 'dart:async';

// ─── Retry ────────────────────────────────────────────────────────────────────

/// Retries [fn] up to [maxAttempts] times with exponential back-off.
///
/// [initialDelay] is doubled on each failure up to [maxDelay].
///
/// Throws the last exception if all attempts fail.
Future<T> retry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 3,
  Duration initialDelay = const Duration(milliseconds: 200),
  Duration maxDelay = const Duration(seconds: 10),
  bool Function(Object error)? retryIf,
}) async {
  var delay = initialDelay;
  Object? lastError;

  for (var attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (e) {
      lastError = e;

      if (retryIf != null && !retryIf(e)) rethrow;
      if (attempt == maxAttempts) rethrow;

      await Future.delayed(delay);
      delay = delay * 2;
      if (delay > maxDelay) delay = maxDelay;
    }
  }

  throw lastError!;
}

// ─── Debounce ────────────────────────────────────────────────────────────────

/// Creates a debounced version of [fn] that delays invocation by [delay].
///
/// Each call resets the timer; [fn] is only called once the timer fires.
void Function() debounce(
  void Function() fn,
  Duration delay,
) {
  Timer? timer;
  return () {
    timer?.cancel();
    timer = Timer(delay, fn);
  };
}

// ─── Throttle ────────────────────────────────────────────────────────────────

/// Creates a throttled version of [fn] that fires at most once per [interval].
void Function() throttle(
  void Function() fn,
  Duration interval,
) {
  DateTime? lastCall;
  return () {
    final now = DateTime.now();
    if (lastCall == null || now.difference(lastCall!) >= interval) {
      lastCall = now;
      fn();
    }
  };
}

// ─── Completer Pool ───────────────────────────────────────────────────────────

/// A pool of completers that can be fulfilled by correlation ID.
class CompleterPool<T> {
  final Map<String, Completer<T>> _completers = {};
  final Duration _defaultTimeout;

  /// Creates a [CompleterPool] with [_defaultTimeout].
  CompleterPool({
    Duration defaultTimeout = const Duration(seconds: 10),
  }) : _defaultTimeout = defaultTimeout;

  /// Creates a new [Completer] for [id] and returns its [Future].
  Future<T> expect(String id, {Duration? timeout}) {
    final completer = Completer<T>();
    _completers[id] = completer;

    final effective = timeout ?? _defaultTimeout;

    Timer(effective, () {
      if (!completer.isCompleted) {
        _completers.remove(id);
        completer.completeError(
          TimeoutException('Timed out waiting for: $id', effective),
        );
      }
    });

    return completer.future;
  }

  /// Completes the future for [id] with [value].
  bool resolve(String id, T value) {
    final completer = _completers.remove(id);
    if (completer == null || completer.isCompleted) return false;
    completer.complete(value);
    return true;
  }

  /// Completes the future for [id] with an [error].
  bool reject(String id, Object error, [StackTrace? st]) {
    final completer = _completers.remove(id);
    if (completer == null || completer.isCompleted) return false;
    completer.completeError(error, st);
    return true;
  }

  /// Whether a pending future for [id] exists.
  bool has(String id) => _completers.containsKey(id);

  /// Number of pending futures.
  int get pendingCount => _completers.length;

  /// Cancels all pending futures with [error].
  void cancelAll([Object error = 'Cancelled']) {
    for (final completer in _completers.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _completers.clear();
  }
}

// ─── Future Timeout Extension ────────────────────────────────────────────────

/// Adds a convenience [withTimeout] that returns `null` instead of throwing.
extension FutureNullableTimeout<T> on Future<T> {
  /// Returns `null` if this future does not complete within [duration].
  Future<T?> orNullOnTimeout(Duration duration) async {
    try {
      return await timeout(duration);
    } on TimeoutException {
      return null;
    }
  }
}
