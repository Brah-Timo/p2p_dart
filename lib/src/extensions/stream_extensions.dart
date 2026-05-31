/// Stream utility extensions.
library;

import 'dart:async';

/// Convenience extensions on [Stream].
extension P2PStreamExtensions<T> on Stream<T> {
  /// Converts this stream to a broadcast stream if it isn't already.
  Stream<T> asBroadcast() =>
      isBroadcast ? this : asBroadcastStream();

  /// Emits the first event of type [S] from this stream.
  Future<S> firstOfType<S>() =>
      where((e) => e is S).cast<S>().first;

  /// Buffers events into lists of [size] and emits each buffer.
  Stream<List<T>> batch(int size) async* {
    final buffer = <T>[];
    await for (final item in this) {
      buffer.add(item);
      if (buffer.length >= size) {
        yield List<T>.from(buffer);
        buffer.clear();
      }
    }
    if (buffer.isNotEmpty) yield buffer;
  }

  /// Applies a debounce: only emits after [duration] of silence.
  Stream<T> debounce(Duration duration) {
    final controller = StreamController<T>.broadcast();
    Timer? timer;

    listen(
      (event) {
        timer?.cancel();
        timer = Timer(duration, () => controller.add(event));
      },
      onError: controller.addError,
      onDone: () {
        timer?.cancel();
        controller.close();
      },
    );

    return controller.stream;
  }

  /// Throttles the stream: emits at most one event per [interval].
  Stream<T> throttle(Duration interval) {
    final controller = StreamController<T>.broadcast();
    DateTime? lastEmit;

    listen(
      (event) {
        final now = DateTime.now();
        if (lastEmit == null || now.difference(lastEmit!) >= interval) {
          lastEmit = now;
          controller.add(event);
        }
      },
      onError: controller.addError,
      onDone: controller.close,
    );

    return controller.stream;
  }

  /// Emits pairs of (previous, current) values.
  Stream<(T, T)> pairwise() async* {
    T? previous;
    var hasPrevious = false;
    await for (final current in this) {
      if (hasPrevious) yield (previous as T, current);
      previous = current;
      hasPrevious = true;
    }
  }
}
