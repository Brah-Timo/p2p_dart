/// Local network peer discovery (mDNS simulation).
library;

import 'dart:async';
import 'dart:io';

import '../core/peer_info.dart';
import '../utils/logger.dart';

// ─── Local Network Discovery ─────────────────────────────────────────────────

/// Discovers peers on the local network segment.
///
/// In a full implementation this uses multicast DNS (mDNS / Zeroconf) to
/// announce and discover peers without any infrastructure.  This class
/// provides the API and a simulated fallback that probes the LAN subnet.
class LocalNetworkDiscovery {
  final P2PLogger _log;

  /// Callback invoked when a new peer is discovered locally.
  late void Function(PeerInfo peer) _onDiscovered;

  final Map<String, PeerInfo> _knownPeers = {};

  bool _running = false;
  Timer? _probeTimer;

  /// Creates a [LocalNetworkDiscovery].
  LocalNetworkDiscovery({P2PLogger? logger})
      : _log = logger ?? P2PLogger('LocalDiscovery');

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  /// Starts local network discovery.
  ///
  /// [onDiscovered] is called for each newly found peer.
  Future<void> start(void Function(PeerInfo peer) onDiscovered) async {
    if (_running) return;
    _running = true;
    _onDiscovered = onDiscovered;

    await _announcePresence();

    // Periodically probe for new peers.
    _probeTimer = Timer.periodic(const Duration(seconds: 30), (_) => _probe());
    _log.info('Local network discovery started.');
  }

  /// Stops discovery.
  void stop() {
    _probeTimer?.cancel();
    _running = false;
  }

  // ─── Lookup ───────────────────────────────────────────────────────────────

  /// Returns the [PeerInfo] for [peerId] if known locally.
  PeerInfo? known(String peerId) => _knownPeers[peerId];

  /// Removes [peerId] from the local peer registry.
  void remove(String peerId) => _knownPeers.remove(peerId);

  // ─── Private ────────────────────────────────────────────────────────────

  Future<void> _announcePresence() async {
    // In production: join mDNS multicast group and send announcement.
    _log.debug('Announcing presence on local network…');
  }

  Future<void> _probe() async {
    if (!_running) return;

    try {
      // Discover local network interfaces.
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          // Only consider private ranges.
          if (_isPrivateIPv4(addr.address)) {
            _log.debug('Local iface ${iface.name}: ${addr.address}');
          }
        }
      }
    } catch (e) {
      _log.debug('Local probe skipped: $e');
    }
  }

  bool _isPrivateIPv4(String ip) {
    return ip.startsWith('10.') ||
        ip.startsWith('192.168.') ||
        ip.startsWith('172.');
  }

  /// Simulates discovery of a local peer (for testing).
  void simulateDiscovery(PeerInfo peer) {
    if (!_knownPeers.containsKey(peer.peerId)) {
      _knownPeers[peer.peerId] = peer;
      if (_running) _onDiscovered(peer);
    }
  }
}
