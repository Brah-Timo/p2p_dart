/// Efficient byte buffer management.
library;

import 'dart:typed_data';

// ─── Growing Buffer ───────────────────────────────────────────────────────────

/// A dynamically growing byte buffer with efficient append and read operations.
class GrowingBuffer {
  Uint8List _buffer;
  int _length = 0;

  /// Initial capacity in bytes.
  static const int _defaultCapacity = 4096;

  /// Creates a [GrowingBuffer] with optional [initialCapacity].
  GrowingBuffer({int initialCapacity = _defaultCapacity})
      : _buffer = Uint8List(initialCapacity);

  // ─── Write ────────────────────────────────────────────────────────────────

  /// Appends [bytes] to the buffer.
  void write(Uint8List bytes) {
    _ensureCapacity(_length + bytes.length);
    _buffer.setRange(_length, _length + bytes.length, bytes);
    _length += bytes.length;
  }

  /// Appends a single [byte].
  void writeByte(int byte) {
    _ensureCapacity(_length + 1);
    _buffer[_length++] = byte;
  }

  /// Appends a 16-bit big-endian integer.
  void writeUint16(int value) {
    writeByte((value >> 8) & 0xFF);
    writeByte(value & 0xFF);
  }

  /// Appends a 32-bit big-endian integer.
  void writeUint32(int value) {
    writeByte((value >> 24) & 0xFF);
    writeByte((value >> 16) & 0xFF);
    writeByte((value >> 8) & 0xFF);
    writeByte(value & 0xFF);
  }

  // ─── Read ─────────────────────────────────────────────────────────────────

  /// Returns the current content as an immutable [Uint8List].
  Uint8List toBytes() => Uint8List.sublistView(_buffer, 0, _length);

  /// Returns the byte at [index].
  int operator [](int index) {
    if (index >= _length) throw RangeError.index(index, this);
    return _buffer[index];
  }

  // ─── State ────────────────────────────────────────────────────────────────

  /// Current number of bytes written.
  int get length => _length;

  /// Whether the buffer is empty.
  bool get isEmpty => _length == 0;

  /// Resets the write position (does not release memory).
  void reset() => _length = 0;

  /// Clears the buffer and releases backing memory.
  void dispose() {
    _buffer = Uint8List(0);
    _length = 0;
  }

  // ─── Private ────────────────────────────────────────────────────────────

  void _ensureCapacity(int required) {
    if (required <= _buffer.length) return;

    var newCapacity = _buffer.length;
    while (newCapacity < required) {
      newCapacity = (newCapacity * 2).clamp(required, 1 << 30);
    }

    final newBuffer = Uint8List(newCapacity);
    newBuffer.setRange(0, _length, _buffer);
    _buffer = newBuffer;
  }
}

// ─── Chunker ─────────────────────────────────────────────────────────────────

/// Splits a large [Uint8List] into fixed-size chunks.
class Chunker {
  /// Splits [data] into chunks of at most [chunkSize] bytes.
  ///
  /// The last chunk may be smaller than [chunkSize].
  static List<Uint8List> split(Uint8List data, int chunkSize) {
    if (data.isEmpty) return [];

    final chunks = <Uint8List>[];
    var offset = 0;

    while (offset < data.length) {
      final end = (offset + chunkSize).clamp(0, data.length);
      chunks.add(Uint8List.sublistView(data, offset, end));
      offset = end;
    }

    return chunks;
  }

  /// Reassembles [chunks] into a single [Uint8List].
  static Uint8List join(List<Uint8List> chunks) {
    final totalLength = chunks.fold(0, (sum, c) => sum + c.length);
    final result = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }
}

// ─── Ring Buffer ─────────────────────────────────────────────────────────────

/// Fixed-capacity ring buffer (circular queue) of [T].
class RingBuffer<T> {
  final List<T?> _buffer;
  int _head = 0;
  int _tail = 0;
  int _count = 0;

  /// Creates a [RingBuffer] with [capacity] slots.
  RingBuffer(int capacity) : _buffer = List.filled(capacity, null);

  /// Whether the buffer is empty.
  bool get isEmpty => _count == 0;

  /// Whether the buffer is full.
  bool get isFull => _count == _buffer.length;

  /// Number of items currently in the buffer.
  int get count => _count;

  /// Enqueues [item].  Returns `false` and drops the item if full.
  bool enqueue(T item) {
    if (isFull) return false;
    _buffer[_tail] = item;
    _tail = (_tail + 1) % _buffer.length;
    _count++;
    return true;
  }

  /// Dequeues and returns the oldest item, or `null` if empty.
  T? dequeue() {
    if (isEmpty) return null;
    final item = _buffer[_head] as T;
    _buffer[_head] = null;
    _head = (_head + 1) % _buffer.length;
    _count--;
    return item;
  }

  /// Peeks at the oldest item without removing it.
  T? peek() => isEmpty ? null : _buffer[_head];

  /// Clears all items.
  void clear() {
    _buffer.fillRange(0, _buffer.length, null);
    _head = _tail = _count = 0;
  }
}
