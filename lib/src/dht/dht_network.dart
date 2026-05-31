/// Kademlia DHT network — peer discovery and distributed storage.
library;

import 'dart:async';

import '../core/enums.dart';
import '../core/exceptions.dart';
import '../core/peer_info.dart';
import '../events/event_bus.dart';
import '../events/events.dart';
import '../utils/logger.dart';
import 'dht_config.dart';
import 'kademlia.dart';
import 'routing_table.dart';

// ─── DHT Record ──────────────────────────────────────────────────────────────

/// A key/value record stored in the DHT.
class DHTRecord {
  /// The 40-char hex key under which the value is stored.
  final String key;

  /// Serialised value (UTF-8 JSON).
  final String value;

  /// Publisher's peer ID.
  final String publisherId;

  /// When this record expires.
  final DateTime expiresAt;

  /// Monotonically increasing sequence number (used for conflict resolution).
  final int sequence;

  /// Creates a [DHTRecord].
  DHTRecord({
    required this.key,
    required this.value,
    required this.publisherId,
    required this.expiresAt,
    this.sequence = 0,
  });

  /// Returns `true` if the record has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Serialises to a JSON map.
  Map<String, dynamic> toJson() => {
        'key': key,
        'value': value,
        'publisherId': publisherId,
        'expiresAt': expiresAt.toIso8601String(),
        'sequence': sequence,
      };

  /// Deserialises from a JSON map.
  factory DHTRecord.fromJson(Map<String, dynamic> json) => DHTRecord(
        key: json['key'] as String,
        value: json['value'] as String,
        publisherId: json['publisherId'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        sequence: (json['sequence'] as int?) ?? 0,
      );

  @override
  String toString() =>
      'DHTRecord(key: ${key.substring(0, 8)}…, '
      'publisher: ${publisherId.substring(0, 8)}…)';
}

// ─── Find Result ─────────────────────────────────────────────────────────────

/// Result of a [DHTNetwork.findPeer] lookup.
class FindPeerResult {
  /// The found peer info, or `null` if not found.
  final PeerInfo? peer;

  /// How the peer was discovered.
  final DiscoveryMethod method;

  /// Number of network hops taken.
  final int hops;

  /// Creates a [FindPeerResult].
  const FindPeerResult({
    this.peer,
    required this.method,
    this.hops = 0,
  });

  /// Returns `true` if the peer was found.
  bool get found => peer != null;
}

// ─── DHT Network ─────────────────────────────────────────────────────────────

/// Kademlia-based Distributed Hash Table.
///
/// Provides:
/// - Iterative peer lookup via FIND_NODE RPCs.
/// - Distributed key/value storage via STORE + FIND_VALUE RPCs.
/// - Periodic bucket refresh and record republication.
///
/// This implementation is *transport-agnostic*: it delegates actual message
/// sending to the [_sendRpc] and [_onRpc] hooks that the [P2PNode] wires up.
class DHTNetwork {
  // ─── Dependencies ──────────────────────────────────────────────────────────

  final String _localId;
  final DHTConfig _config;
  final EventBus _eventBus;
  final P2PLogger _log;

  // ─── State ─────────────────────────────────────────────────────────────────

  late RoutingTable _routingTable;

  /// Locally stored DHT records.
  final Map<String, DHTRecord> _store = {};

  /// Background timers.
  Timer? _refreshTimer;
  Timer? _republishTimer;
  Timer? _expireTimer;

  bool _running = false;

  // ─── RPC Hooks (injected by P2PNode) ──────────────────────────────────────

  /// Called to send a DHT RPC to a remote peer.
  ///
  /// Returns the raw response map (already decoded) or throws on timeout.
  Future<Map<String, dynamic>> Function(
    String targetPeerId,
    Map<String, dynamic> rpc,
  )? _sendRpc;

  // ─── Constructor ───────────────────────────────────────────────────────────

  /// Creates a [DHTNetwork].
  DHTNetwork({
    required String localId,
    required DHTConfig config,
    required EventBus eventBus,
    P2PLogger? logger,
  })  : _localId = localId,
        _config = config,
        _eventBus = eventBus,
        _log = logger ?? P2PLogger('DHT');

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  /// Wires in the RPC transport function.
  void setRpcTransport(
    Future<Map<String, dynamic>> Function(
      String targetPeerId,
      Map<String, dynamic> rpc,
    ) fn,
  ) {
    _sendRpc = fn;
  }

  /// Starts the DHT, creating the routing table and background tasks.
  Future<void> start() async {
    if (_running) return;
    _routingTable = RoutingTable(_localId, k: _config.bucketSize);
    _running = true;

    // Start periodic tasks.
    _refreshTimer = Timer.periodic(
      _config.bucketRefreshInterval,
      (_) => _refreshBuckets(),
    );
    _republishTimer = Timer.periodic(
      _config.republishInterval,
      (_) => _republishRecords(),
    );
    _expireTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _expireRecords(),
    );

    _log.info('DHT started. Local ID: $_localId');
  }

  /// Bootstraps into the network by connecting to [_config.bootstrapPeers].
  Future<void> bootstrap(List<PeerInfo> seedPeers) async {
    if (!_running) throw const DHTException('DHT is not running');

    for (final seed in seedPeers) {
      _routingTable.add(seed);
    }

    // Perform a self-lookup to populate the routing table.
    try {
      await findPeer(_localId);
    } catch (_) {
      // Expected to fail (we are looking for ourselves).
    }

    _eventBus.emit(DHTBootstrappedEvent(_localId));
    _log.info('DHT bootstrapped with ${seedPeers.length} seed peers.');
  }

  /// Stops background timers and clears state.
  Future<void> stop() async {
    _refreshTimer?.cancel();
    _republishTimer?.cancel();
    _expireTimer?.cancel();
    _running = false;
    _log.info('DHT stopped.');
  }

  // ─── Peer Lookup ──────────────────────────────────────────────────────────

  /// Performs an iterative Kademlia FIND_NODE lookup for [targetId].
  ///
  /// Returns [FindPeerResult] — [FindPeerResult.found] is `true` if the peer
  /// was located.
  Future<FindPeerResult> findPeer(String targetId) async {
    _log.debug('findPeer: $targetId');

    // 1. Check routing table directly.
    final local = _routingTable.find(targetId);
    if (local != null) {
      return FindPeerResult(
        peer: local,
        method: DiscoveryMethod.dhtRoutingTable,
      );
    }

    // 2. Iterative lookup.
    final result = await _iterativeLookup(targetId, findValue: false);
    final peer = result['peer'] as PeerInfo?;

    return FindPeerResult(
      peer: peer,
      method: DiscoveryMethod.dhtLookup,
      hops: result['hops'] as int,
    );
  }

  // ─── Key / Value Store ────────────────────────────────────────────────────

  /// Stores [value] under [key] across [_config.replicationFactor] closest peers.
  Future<void> put(String key, String value) async {
    final hashedKey = Kademlia.keyFromString(key);
    final record = DHTRecord(
      key: hashedKey,
      value: value,
      publisherId: _localId,
      expiresAt: DateTime.now().add(_config.valueTtl),
      sequence: _nextSequence(hashedKey),
    );

    // Store locally.
    _store[hashedKey] = record;

    // Replicate to the k closest peers.
    final closest = _routingTable.closest(
      hashedKey,
      count: _config.replicationFactor,
    );

    final futures = closest.map(
      (peer) => _sendRpcStore(peer.peerId, record),
    );
    await Future.wait(futures, eagerError: false);

    _eventBus.emit(DHTValueStoredEvent(hashedKey, value));
    _log.debug('put: $key → ${closest.length} peers');
  }

  /// Retrieves the value for [key], searching locally then across the network.
  Future<String?> get(String key) async {
    final hashedKey = Kademlia.keyFromString(key);

    // Local hit.
    final local = _store[hashedKey];
    if (local != null && !local.isExpired) return local.value;

    // Remote lookup.
    final result = await _iterativeLookup(hashedKey, findValue: true);
    return result['value'] as String?;
  }

  /// Deletes the record for [key] from the local store.
  ///
  /// Note: distributed deletion is not supported by Kademlia; records expire
  /// naturally via their TTL.
  void delete(String key) {
    final hashedKey = Kademlia.keyFromString(key);
    _store.remove(hashedKey);
  }

  // ─── Routing Table Accessors ──────────────────────────────────────────────

  /// Adds or refreshes a peer in the routing table.
  void addPeer(PeerInfo peer) => _routingTable.add(peer);

  /// Removes a peer from the routing table.
  void removePeer(String peerId) => _routingTable.remove(peerId);

  /// Marks [peerId] as recently seen.
  void touchPeer(String peerId) => _routingTable.touch(peerId);

  /// Records a failed RPC attempt to [peerId].
  void recordFailure(String peerId) => _routingTable.recordFailure(peerId);

  /// Returns the [count] closest peers to [targetId] known locally.
  List<PeerInfo> closestKnown(String targetId, {int count = 20}) =>
      _routingTable.closest(targetId, count: count);

  /// Total peers in the routing table.
  int get peerCount => _routingTable.size;

  // ─── Incoming RPC Dispatch ────────────────────────────────────────────────

  /// Handles an incoming DHT RPC message from [senderId].
  ///
  /// Returns the response map (to be forwarded back to the sender).
  Map<String, dynamic> handleRpc(
    String senderId,
    Map<String, dynamic> rpc,
  ) {
    _routingTable.touch(senderId);

    final type = rpc['type'] as String;
    switch (type) {
      case 'PING':
        return _handlePing(senderId);
      case 'FIND_NODE':
        return _handleFindNode(senderId, rpc);
      case 'FIND_VALUE':
        return _handleFindValue(senderId, rpc);
      case 'STORE':
        return _handleStore(senderId, rpc);
      default:
        return {'error': 'Unknown RPC type: $type'};
    }
  }

  // ─── RPC Handlers ────────────────────────────────────────────────────────

  Map<String, dynamic> _handlePing(String senderId) =>
      {'type': 'PONG', 'nodeId': _localId};

  Map<String, dynamic> _handleFindNode(
    String senderId,
    Map<String, dynamic> rpc,
  ) {
    final targetId = rpc['targetId'] as String;
    final closest = _routingTable.closest(targetId, count: _config.bucketSize);
    return {
      'type': 'FOUND_NODES',
      'nodeId': _localId,
      'nodes': closest.map((p) => p.toJson()).toList(),
    };
  }

  Map<String, dynamic> _handleFindValue(
    String senderId,
    Map<String, dynamic> rpc,
  ) {
    final key = rpc['key'] as String;
    final local = _store[key];
    if (local != null && !local.isExpired) {
      return {
        'type': 'FOUND_VALUE',
        'nodeId': _localId,
        'value': local.value,
      };
    }
    // Fall back to returning closest nodes.
    final closest = _routingTable.closest(key, count: _config.bucketSize);
    return {
      'type': 'FOUND_NODES',
      'nodeId': _localId,
      'nodes': closest.map((p) => p.toJson()).toList(),
    };
  }

  Map<String, dynamic> _handleStore(
    String senderId,
    Map<String, dynamic> rpc,
  ) {
    try {
      final record = DHTRecord.fromJson(rpc['record'] as Map<String, dynamic>);
      final existing = _store[record.key];

      if (existing == null || record.sequence > existing.sequence) {
        _store[record.key] = record;
      }

      return {'type': 'STORED', 'nodeId': _localId};
    } catch (e) {
      return {'type': 'ERROR', 'message': e.toString()};
    }
  }

  // ─── Iterative Lookup ─────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _iterativeLookup(
    String targetId, {
    required bool findValue,
  }) async {
    final queried = <String>{};
    var closest = _routingTable.closest(targetId, count: _config.alpha);
    int hops = 0;

    while (hops < _config.maxLookupHops) {
      final toQuery = closest
          .where((p) => !queried.contains(p.peerId))
          .take(_config.alpha)
          .toList();

      if (toQuery.isEmpty) break;

      hops++;

      final responses = await Future.wait(
        toQuery.map((peer) async {
          queried.add(peer.peerId);
          try {
            return await _sendRpcWithTimeout(
              peer.peerId,
              findValue
                  ? {'type': 'FIND_VALUE', 'key': targetId}
                  : {'type': 'FIND_NODE', 'targetId': targetId},
            );
          } catch (_) {
            _routingTable.recordFailure(peer.peerId);
            return null;
          }
        }),
        eagerError: false,
      );

      bool converged = true;

      for (final response in responses) {
        if (response == null) continue;

        if (findValue && response['type'] == 'FOUND_VALUE') {
          return {
            'value': response['value'],
            'hops': hops,
            'peer': null,
          };
        }

        if (response['nodes'] != null) {
          final nodes = (response['nodes'] as List<dynamic>)
              .map((n) => PeerInfo.fromJson(n as Map<String, dynamic>))
              .toList();

          for (final node in nodes) {
            if (!queried.contains(node.peerId)) {
              _routingTable.add(node);
              converged = false;
            }

            if (node.peerId == targetId) {
              return {'peer': node, 'hops': hops};
            }
          }
        }
      }

      if (converged) break;

      // Refresh closest list.
      closest = _routingTable.closest(targetId, count: _config.bucketSize);
    }

    return {'peer': null, 'value': null, 'hops': hops};
  }

  // ─── Background Tasks ────────────────────────────────────────────────────

  Future<void> _refreshBuckets() async {
    for (final bucket in _routingTable.staleBuckets) {
      final randomId = _routingTable.randomIdInBucket(bucket);
      try {
        await _iterativeLookup(randomId, findValue: false);
        bucket.markRefreshed();
      } catch (e) {
        _log.warning('Bucket refresh failed: $e');
      }
    }
  }

  Future<void> _republishRecords() async {
    for (final record in _store.values.toList()) {
      if (!record.isExpired) {
        await put(record.key, record.value);
      }
    }
  }

  void _expireRecords() {
    _store.removeWhere((_, record) => record.isExpired);
  }

  // ─── Private Helpers ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _sendRpcStore(
    String peerId,
    DHTRecord record,
  ) async {
    try {
      return await _sendRpcWithTimeout(
        peerId,
        {'type': 'STORE', 'record': record.toJson()},
      );
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, dynamic>> _sendRpcWithTimeout(
    String peerId,
    Map<String, dynamic> rpc,
  ) async {
    final fn = _sendRpc;
    if (fn == null) return {};

    return fn(peerId, rpc).timeout(
      _config.rpcTimeout,
      onTimeout: () => {'error': 'timeout'},
    );
  }

  int _nextSequence(String key) {
    final existing = _store[key];
    return existing != null ? existing.sequence + 1 : 1;
  }
}
