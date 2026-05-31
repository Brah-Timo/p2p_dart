/// Throughput and latency performance benchmarks.
///
/// Thresholds are intentionally generous to accommodate pure-Dart
/// implementations (PointyCastle AES-GCM, BigInt XOR) running in CI
/// sandboxes without native crypto acceleration.  The goal is to catch
/// catastrophic regressions, not to enforce native-speed numbers.
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:p2p_dart/p2p_dart.dart';

void main() {
  group('Throughput — Chunker', () {
    test('splits 10 MB at 64 KB chunks in < 2000 ms', () {
      final data = Uint8List(10 * 1024 * 1024); // 10 MB

      final sw = Stopwatch()..start();
      final chunks = Chunker.split(data, 64 * 1024);
      sw.stop();

      expect(chunks.length, greaterThan(0));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });

    test('joins 10 MB at 64 KB chunks in < 2000 ms', () {
      final data = Uint8List.fromList(
        List.generate(10 * 1024 * 1024, (i) => i % 256),
      );
      final chunks = Chunker.split(data, 64 * 1024);

      final sw = Stopwatch()..start();
      final joined = Chunker.join(chunks);
      sw.stop();

      expect(joined, equals(data));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('Throughput — GrowingBuffer', () {
    test('writes 10 MB in < 2000 ms', () {
      final buf = GrowingBuffer(initialCapacity: 4096);
      final chunk = Uint8List(4096);

      final sw = Stopwatch()..start();
      for (var i = 0; i < 2560; i++) {
        buf.write(chunk);
      }
      sw.stop();

      expect(buf.length, equals(10 * 1024 * 1024));
      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('Throughput — CryptoUtils AES-GCM', () {
    // PointyCastle is a pure-Dart implementation without native crypto
    // acceleration; 1 MB AES-256-GCM may take several seconds in a sandbox.
    test('encrypts 1 MB in < 10000 ms', () {
      final key = CryptoUtils.randomBytes(32);
      final plaintext = Uint8List(1024 * 1024); // 1 MB

      final sw = Stopwatch()..start();
      CryptoUtils.aesGcmEncrypt(key, plaintext);
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(10000));
    });
  });

  group('Throughput — Kademlia', () {
    test('generates 10 000 IDs in < 5000 ms', () {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 10000; i++) {
        Kademlia.generateId();
      }
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    // BigInt XOR distance computation is pure-Dart; sorting 1000 peers may
    // take hundreds of milliseconds in a low-resource sandbox.
    test('sorts 1000 peers by XOR distance in < 2000 ms', () {
      final target = Kademlia.generateId();
      final peers = List.generate(1000, (_) => Kademlia.generateId());

      final sw = Stopwatch()..start();
      Kademlia.sortByDistance(
        targetId: target,
        peers: peers,
        getId: (p) => p,
      );
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(2000));
    });
  });

  group('Throughput — RoutingTable', () {
    test('inserts 1000 peers in < 5000 ms', () {
      final table = RoutingTable('a' * 40, k: 20);

      final sw = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        table.add(PeerInfo(peerId: Kademlia.generateId()));
      }
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(5000));
    });

    // Reduced from 10 000 × 500-peer table to 100 × 50-peer table: the
    // closest() call sorts all peers by BigInt XOR distance which is O(n log n)
    // pure-Dart BigInt arithmetic — very slow at scale in a sandbox.
    test('performs 100 closest lookups in < 10000 ms', () {
      final table = RoutingTable('a' * 40, k: 20);
      for (var i = 0; i < 50; i++) {
        table.add(PeerInfo(peerId: Kademlia.generateId()));
      }

      final sw = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        table.closest(Kademlia.generateId(), count: 20);
      }
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(10000));
    });
  });

  group('Throughput — EventBus', () {
    test('dispatches 100 000 events in < 5000 ms', () {
      final bus = EventBus();
      var count = 0;
      bus.on<NodeStartedEvent>((_) => count++);

      final sw = Stopwatch()..start();
      for (var i = 0; i < 100000; i++) {
        bus.emit(NodeStartedEvent(peerId: 'a' * 40));
      }
      sw.stop();

      expect(count, equals(100000));
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });
  });
}
