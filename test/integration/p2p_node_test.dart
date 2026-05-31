/// Integration tests for [P2PNode].
library;

import 'dart:async';

import 'package:test/test.dart';
import 'package:p2p_dart/p2p_dart.dart';

void main() {
  group('P2PNode — lifecycle', () {
    late P2PNode node;

    setUp(() {
      node = P2PNode(
        config: P2PConfig(
          logging: LoggingConfig(verbose: false),
        ),
      );
    });

    tearDown(() async {
      if (node.isOnline) await node.stop();
    });

    test('initialises successfully', () async {
      await node.initialize();
      expect(node.isOnline, isTrue);
      expect(node.status, equals(NodeStatus.online));
    });

    test('assigns a valid peer ID', () async {
      await node.initialize();
      expect(Kademlia.isValidId(node.peerId), isTrue);
    });

    test('stops cleanly', () async {
      await node.initialize();
      await node.stop();
      expect(node.status, equals(NodeStatus.offline));
    });

    test('emits NodeStartedEvent', () async {
      final completer = Completer<NodeStartedEvent>();
      node.eventBus.once<NodeStartedEvent>(completer.complete);
      await node.initialize();
      final event = await completer.future.timeout(const Duration(seconds: 5));
      expect(event.peerId, equals(node.peerId));
    });

    test('emits NodeStoppedEvent', () async {
      await node.initialize();
      final completer = Completer<NodeStoppedEvent>();
      node.eventBus.once<NodeStoppedEvent>(completer.complete);
      await node.stop();
      await completer.future.timeout(const Duration(seconds: 5));
    });

    test('throws on double initialise', () async {
      await node.initialize();
      expect(
        () => node.initialize(),
        throwsA(isA<InitializationException>()),
      );
    });

    test('throws SelfConnectionException on connect-to-self', () async {
      await node.initialize();
      expect(
        () => node.connect(node.peerId),
        throwsA(isA<SelfConnectionException>()),
      );
    });

    test('throws when sending to disconnected peer', () async {
      await node.initialize();
      final fakePeerId = Kademlia.generateId();
      expect(
        () => node.send(fakePeerId, {'test': true}),
        throwsA(isA<ConnectionClosedException>()),
      );
    });

    test('throws InitializationException when not online', () async {
      expect(
        () => node.send(Kademlia.generateId(), {}),
        throwsA(isA<InitializationException>()),
      );
    });
  });

  group('P2PNode — DHT operations', () {
    late P2PNode node;

    setUpAll(() async {
      node = P2PNode(config: P2PConfig());
      await node.initialize();
    });

    tearDownAll(() async {
      await node.stop();
    });

    test('dhtPut and dhtGet round-trip', () async {
      await node.dhtPut('test-key', 'hello-world');
      final value = await node.dhtGet('test-key');
      expect(value, equals('hello-world'));
    });

    test('dhtGet returns null for unknown key', () async {
      final value = await node.dhtGet('nonexistent-${DateTime.now().millisecondsSinceEpoch}');
      expect(value, isNull);
    });

    test('dhtPut overwrites existing value', () async {
      await node.dhtPut('overwrite-key', 'original');
      await node.dhtPut('overwrite-key', 'updated');
      final value = await node.dhtGet('overwrite-key');
      expect(value, equals('updated'));
    });
  });

  group('P2PNode — two-node communication', () {
    late P2PNode nodeA;
    late P2PNode nodeB;

    setUpAll(() async {
      nodeA = P2PNode(config: P2PConfig());
      nodeB = P2PNode(config: P2PConfig());

      await nodeA.initialize();
      await nodeB.initialize();
    });

    tearDownAll(() async {
      await nodeA.stop();
      await nodeB.stop();
    });

    test('broadcast does not throw with no connections', () async {
      await expectLater(
        nodeA.broadcast({'hello': 'world'}),
        completes,
      );
    });

    test('connectedPeerIds is empty initially', () {
      expect(nodeA.connectedPeerIds, isEmpty);
    });

    test('connectionCount is zero initially', () {
      expect(nodeA.connectionCount, isZero);
    });
  });
}
