/// Unit tests for buffer utilities.
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:p2p_dart/p2p_dart.dart';

void main() {
  group('GrowingBuffer', () {
    test('write and toBytes round-trip', () {
      final buf = GrowingBuffer();
      final data = Uint8List.fromList([1, 2, 3, 4, 5]);
      buf.write(data);
      expect(buf.toBytes(), equals(data));
    });

    test('writeByte appends correctly', () {
      final buf = GrowingBuffer();
      buf.writeByte(0xAA);
      buf.writeByte(0xBB);
      expect(buf.toBytes(), equals(Uint8List.fromList([0xAA, 0xBB])));
    });

    test('writeUint32 big-endian', () {
      final buf = GrowingBuffer();
      buf.writeUint32(0x01020304);
      expect(buf.toBytes(), equals(Uint8List.fromList([0x01, 0x02, 0x03, 0x04])));
    });

    test('length tracks written bytes', () {
      final buf = GrowingBuffer();
      expect(buf.length, isZero);
      buf.write(Uint8List(100));
      expect(buf.length, equals(100));
    });

    test('reset clears length', () {
      final buf = GrowingBuffer();
      buf.write(Uint8List(50));
      buf.reset();
      expect(buf.length, isZero);
    });

    test('handles writes larger than initial capacity', () {
      final buf = GrowingBuffer(initialCapacity: 4);
      final large = Uint8List.fromList(List.generate(10000, (i) => i % 256));
      buf.write(large);
      expect(buf.toBytes(), equals(large));
    });
  });

  group('Chunker', () {
    test('split divides data into equal-sized chunks', () {
      final data = Uint8List.fromList(List.generate(100, (i) => i));
      final chunks = Chunker.split(data, 25);
      expect(chunks.length, equals(4));
      for (final chunk in chunks) {
        expect(chunk.length, equals(25));
      }
    });

    test('last chunk is smaller when data is not divisible', () {
      final data = Uint8List.fromList(List.generate(101, (i) => i));
      final chunks = Chunker.split(data, 25);
      expect(chunks.length, equals(5));
      expect(chunks.last.length, equals(1));
    });

    test('join reassembles chunks', () {
      final data = Uint8List.fromList(List.generate(200, (i) => i % 256));
      final chunks = Chunker.split(data, 30);
      final joined = Chunker.join(chunks);
      expect(joined, equals(data));
    });

    test('split of empty data returns empty list', () {
      expect(Chunker.split(Uint8List(0), 64), isEmpty);
    });
  });

  group('RingBuffer', () {
    test('enqueue and dequeue FIFO order', () {
      final ring = RingBuffer<int>(5);
      ring.enqueue(1);
      ring.enqueue(2);
      ring.enqueue(3);
      expect(ring.dequeue(), equals(1));
      expect(ring.dequeue(), equals(2));
      expect(ring.dequeue(), equals(3));
    });

    test('returns false when full', () {
      final ring = RingBuffer<int>(2);
      expect(ring.enqueue(1), isTrue);
      expect(ring.enqueue(2), isTrue);
      expect(ring.enqueue(3), isFalse); // full
    });

    test('dequeue returns null when empty', () {
      final ring = RingBuffer<int>(4);
      expect(ring.dequeue(), isNull);
    });

    test('peek does not remove item', () {
      final ring = RingBuffer<int>(4);
      ring.enqueue(42);
      expect(ring.peek(), equals(42));
      expect(ring.count, equals(1));
    });

    test('clear empties the buffer', () {
      final ring = RingBuffer<int>(4);
      ring
        ..enqueue(1)
        ..enqueue(2)
        ..clear();
      expect(ring.isEmpty, isTrue);
    });
  });
}
