/// Peer discovery orchestrator.
library;

import 'dart:async';

import '../core/enums.dart';
import '../core/peer_info.dart';
import '../events/event_bus.dart';
import '../events/events.dart';
import '../utils/logger.dart';
import 'local_network.dart';
import 'peer_cache.dart';

// ─── Discovery Result ─────────────────────────────────────────────────────────

/// Result from a peer discovery operation.
class DiscoveryResult {
  /// Found peers.
  final List<PeerInfo> peers;

  /// How they were discovered.
  final DiscoveryMethod method;

  /// Creates a [DiscoveryResult].
  const DiscoveryResult({required this.peers, required this.method});

  @override
  String toString() =>
      'DiscoveryResult(peers: ${peers.length}, method: $method)';
}

// ─── Peer Discovery ───────────────────────────────────────────────────────────

/// Orchestrates multiple peer discovery strategies.
///
/// Currently supports:
/// 1. **In-memory cache** — fastest lookup.
/// 2. **Local network mDNS** — for LAN peers.
/// 3. **DHT** — delegated to [DHTNetwork] (wired externally).
class PeerDiscovery {
  final EventBus _eventBus;
  final PeerCache _cache;
  final LocalNetworkDiscovery _local;
  final P2PLogger _log;

  bool _running = false;

  // ─── Constructor ───────────────────────────────────────────────────────────

  /// Creates a [PeerDiscovery] instance.
  PeerDiscovery({
    required EventBus eventBus,
    PeerCache? cache,
    LocalNetworkDiscovery? localDiscovery,
    P2PLogger? logger,
  })  : _eventBus = eventBus,
        _cache = cache ?? PeerCache(),
        _local = localDiscovery ?? LocalNetworkDiscovery(),
        _log = logger ?? P2PLogger('PeerDiscovery');

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  /// Starts background discovery (mDNS, cache refresh, etc.).
  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _local.start(_onLocalPeerDiscovered);
    _log.info('PeerDiscovery started.');
  }

  /// Stops background discovery.
  Future<void> stop() async {
    _running = false;
    _local.stop();
    _log.info('PeerDiscovery stopped.');
  }

  // ─── Lookup ───────────────────────────────────────────────────────────────

  /// Looks up [peerId] using all available methods in priority order.
  ///
  /// Returns the first [DiscoveryResult] that contains the peer, or a
  /// result with an empty list if not found.
  Future<DiscoveryResult> find(String peerId) async {
    // 1. Cache hit.
    final cached = _cache.get(peerId);
    if (cached != null) {
      return DiscoveryResult(
        peers: [cached],
        method: DiscoveryMethod.cache,
      );
    }

    // 2. Local network.
    final local = _local.known(peerId);
    if (local != null) {
      _cache.put(local);
      return DiscoveryResult(
        peers: [local],
        method: DiscoveryMethod.mDns,
      );
    }

    // 3. Not found locally — caller should try DHT.
    return const DiscoveryResult(
      peers: [],
      method: DiscoveryMethod.dhtLookup,
    );
  }

  // ─── Cache Maintenance ────────────────────────────────────────────────────

  /// Adds a [PeerInfo] to the local cache (e.g. after a DHT lookup).
  void addToCache(PeerInfo peer) => _cache.put(peer);

  /// Removes a peer from all caches (called on disconnect).
  void remove(String peerId) {
    _cache.remove(peerId);
    _local.remove(peerId);
  }

  // ─── Private ────────────────────────────────────────────────────────────

  void _onLocalPeerDiscovered(PeerInfo peer) {
    _cache.put(peer);
    _eventBus.emit(PeerDiscoveredEvent(peerInfo: peer));
    _log.debug('Locally discovered: ${peer.peerId}');
  }
}
