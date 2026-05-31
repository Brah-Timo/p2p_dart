/// Unit tests for the Kademlia ID utilities.
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:p2p_dart/p2p_dart.dart';

void main() {
  group('Kademlia', () {
    test('generateId produces a valid 40-char hex ID', () {
      final id = Kademlia.generateId();
      expect(id.length, equals(40));
      expect(RegExp(r'^[0-9a-f]{40}$').hasMatch(id), isTrue);
    });

    test('generateId produces unique IDs', () {
      final ids = {for (var i = 0; i < 1000; i++) Kademlia.generateId()};
      expect(ids.length, equals(1000));
    });

    test('isValidId accepts valid hex IDs', () {
      expect(Kademlia.isValidId('a' * 40), isTrue);
      expect(Kademlia.isValidId('0123456789abcdef01234567890abcdef0123456'), isTrue);
    });

    test('isValidId rejects invalid IDs', () {
      expect(Kademlia.isValidId(''), isFalse);
      expect(Kademlia.isValidId('abc'), isFalse);
      expect(Kademlia.isValidId('z' * 40), isFalse); // 'z' is not hex
    });

    test('distance is zero for identical IDs', () {
      final id = Kademlia.generateId();
      expect(Kademlia.distance(id, id), equals(BigInt.zero));
    });

    test('distance is commutative', () {
      final a = Kademlia.generateId();
      final b = Kademlia.generateId();
      expect(Kademlia.distance(a, b), equals(Kademlia.distance(b, a)));
    });

    test('distance satisfies triangle inequality', () {
      final a = Kademlia.generateId();
      final b = Kademlia.generateId();
      final c = Kademlia.generateId();
      final ab = Kademlia.distance(a, b);
      final bc = Kademlia.distance(b, c);
      final ac = Kademlia.distance(a, c);
      expect(ac <= ab + bc, isTrue);
    });

    test('sortByDistance orders peers correctly', () {
      final target = Kademlia.generateId();
      final peers = List.generate(10, (_) => Kademlia.generateId());

      final sorted = Kademlia.sortByDistance(
        targetId: target,
        peers: peers,
        getId: (p) => p,
      );

      for (var i = 0; i < sorted.length - 1; i++) {
        final d1 = Kademlia.distance(target, sorted[i]);
        final d2 = Kademlia.distance(target, sorted[i + 1]);
        expect(d1 <= d2, isTrue);
      }
    });

    test('closestN returns at most N items', () {
      final target = Kademlia.generateId();
      final peers = List.generate(20, (_) => Kademlia.generateId());

      final closest = Kademlia.closestN(
        targetId: target,
        candidates: peers,
        getId: (p) => p,
        count: 5,
      );

      expect(closest.length, lessThanOrEqualTo(5));
    });

    test('idFromPublicKey is deterministic', () {
      final key = List.generate(32, (i) => i).toList();
      final bytes = Uint8List.fromList(key);
      final id1 = Kademlia.idFromPublicKey(bytes);
      final id2 = Kademlia.idFromPublicKey(bytes);
      expect(id1, equals(id2));
    });
  });
}
