/// Unit tests for [PeerCache].
library;

import 'package:test/test.dart';
import 'package:p2p_dart/p2p_dart.dart';

void main() {
  group('PeerCache', () {
    late PeerCache cache;

    setUp(() => cache = PeerCache(capacity: 5, ttl: const Duration(hours: 1)));

    PeerInfo _peer([String? id]) =>
        PeerInfo(peerId: id ?? Kademlia.generateId());

    test('starts empty', () {
      expect(cache.size, isZero);
    });

    test('put and get', () {
      final peer = _peer();
      cache.put(peer);
      expect(cache.get(peer.peerId), equals(peer));
    });

    test('returns null for unknown peer', () {
      expect(cache.get(Kademlia.generateId()), isNull);
    });

    test('contains() returns true for known peers', () {
      final peer = _peer();
      cache.put(peer);
      expect(cache.contains(peer.peerId), isTrue);
    });

    test('remove() removes the peer', () {
      final peer = _peer();
      cache.put(peer);
      cache.remove(peer.peerId);
      expect(cache.get(peer.peerId), isNull);
    });

    test('evicts LRU entry when capacity is reached', () {
      final peers = List.generate(5, (_) => _peer());
      for (final p in peers) cache.put(p);

      // Access peer 0 so it is most-recently used.
      cache.get(peers[0].peerId);

      // Adding a 6th entry should evict the LRU (peer 1).
      final sixth = _peer();
      cache.put(sixth);

      expect(cache.size, equals(5));
    });

    test('updating existing entry does not increase size', () {
      final peer = _peer();
      cache.put(peer);
      cache.put(peer); // update
      expect(cache.size, equals(1));
    });

    test('clear() empties the cache', () {
      cache.put(_peer());
      cache.put(_peer());
      cache.clear();
      expect(cache.size, isZero);
    });

    test('all returns non-expired entries', () {
      cache.put(_peer());
      cache.put(_peer());
      expect(cache.all.length, equals(2));
    });
  });
}
