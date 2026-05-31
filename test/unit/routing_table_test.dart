/// Unit tests for [RoutingTable].
library;

import 'package:test/test.dart';
import 'package:p2p_dart/p2p_dart.dart';

void main() {
  late RoutingTable table;
  final localId = 'a' * 40;

  setUp(() {
    table = RoutingTable(localId, k: 20);
  });

  group('RoutingTable', () {
    test('starts empty', () {
      expect(table.size, isZero);
      expect(table.allPeers, isEmpty);
    });

    test('does not add self', () {
      final self = PeerInfo(peerId: localId);
      final added = table.add(self);
      expect(added, isFalse);
      expect(table.size, isZero);
    });

    test('adds and retrieves a peer', () {
      final peer = PeerInfo(peerId: Kademlia.generateId());
      table.add(peer);
      expect(table.find(peer.peerId), equals(peer));
    });

    test('updates existing peer entry', () {
      final peerId = Kademlia.generateId();
      final peer1 = PeerInfo(peerId: peerId);
      final peer2 = PeerInfo(
        peerId: peerId,
        displayName: 'Updated',
      );
      table.add(peer1);
      table.add(peer2);
      expect(table.size, equals(1));
      expect(table.find(peerId)?.displayName, equals('Updated'));
    });

    test('removes a peer', () {
      final peer = PeerInfo(peerId: Kademlia.generateId());
      table.add(peer);
      final removed = table.remove(peer.peerId);
      expect(removed, isTrue);
      expect(table.find(peer.peerId), isNull);
      expect(table.size, isZero);
    });

    test('returns closest N peers', () {
      for (var i = 0; i < 30; i++) {
        table.add(PeerInfo(peerId: Kademlia.generateId()));
      }
      final target = Kademlia.generateId();
      final closest = table.closest(target, count: 5);
      expect(closest.length, lessThanOrEqualTo(5));
    });

    test('closest peers are ordered by XOR distance', () {
      for (var i = 0; i < 20; i++) {
        table.add(PeerInfo(peerId: Kademlia.generateId()));
      }
      final target = Kademlia.generateId();
      final closest = table.closest(target, count: 10);

      for (var i = 0; i < closest.length - 1; i++) {
        final d1 = Kademlia.distance(target, closest[i].peerId);
        final d2 = Kademlia.distance(target, closest[i + 1].peerId);
        expect(d1 <= d2, isTrue);
      }
    });

    test('touch moves peer to tail', () {
      final peer = PeerInfo(peerId: Kademlia.generateId());
      table.add(peer);
      table.touch(peer.peerId);
      expect(table.find(peer.peerId), isNotNull);
    });

    test('recordFailure eventually evicts a dead peer', () {
      final peer = PeerInfo(peerId: Kademlia.generateId());
      table.add(peer);

      for (var i = 0; i < 3; i++) {
        table.recordFailure(peer.peerId);
      }

      // After 3 failures the peer should be evicted.
      expect(table.find(peer.peerId), isNull);
    });
  });
}
