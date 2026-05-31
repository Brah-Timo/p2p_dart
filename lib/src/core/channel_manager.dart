/// Manages the set of active [Connection]s for a node.
library;

import 'dart:async';

import '../core/connection.dart';
import '../core/enums.dart';
import '../core/exceptions.dart';
import '../utils/logger.dart';

// ─── Channel Manager ─────────────────────────────────────────────────────────

/// Tracks and manages all [Connection]s owned by a [P2PNode].
///
/// Responsibilities:
/// - Keyed connection store (by remote peer ID).
/// - Automatic removal of closed connections.
/// - Broadcast helpers (send to all / send to subset).
/// - Connection-count limit enforcement.
class ChannelManager {
  final int _maxConnections;
  final P2PLogger _log;

  final Map<String, Connection> _connections = {};

  // ─── Streams ───────────────────────────────────────────────────────────────

  final StreamController<Connection> _connectedController =
      StreamController.broadcast();
  final StreamController<String> _disconnectedController =
      StreamController.broadcast();

  /// Fires when a new [Connection] is added.
  Stream<Connection> get onConnected => _connectedController.stream;

  /// Fires with the remote peer ID when a connection is removed.
  Stream<String> get onDisconnected => _disconnectedController.stream;

  // ─── Constructor ───────────────────────────────────────────────────────────

  /// Creates a [ChannelManager].
  ChannelManager({
    int maxConnections = 100,
    P2PLogger? logger,
  })  : _maxConnections = maxConnections,
        _log = logger ?? P2PLogger('ChannelManager');

  // ─── Registration ─────────────────────────────────────────────────────────

  /// Adds [connection] to the manager.
  ///
  /// Throws [ConnectionException] if [_maxConnections] is reached.
  void add(Connection connection) {
    if (_connections.length >= _maxConnections) {
      throw ConnectionException(
        'Max connections reached ($_maxConnections)',
        peerId: connection.remotePeerId,
      );
    }

    // Replace any existing (likely stale) connection for the same peer.
    final existing = _connections[connection.remotePeerId];
    if (existing != null && existing.state != ConnectionState.closed) {
      _log.warning(
        'Replacing existing connection to ${connection.remotePeerId}',
      );
      existing.close().ignore();
    }

    _connections[connection.remotePeerId] = connection;

    // Auto-remove when closed.
    connection.onStateChange
        .where((s) => s == ConnectionState.closed)
        .take(1)
        .listen((_) => _remove(connection.remotePeerId));

    _connectedController.add(connection);
    _log.debug('Connection added: ${connection.remotePeerId}');
  }

  /// Removes and closes the connection to [peerId] (if any).
  Future<void> remove(String peerId) async {
    final conn = _connections.remove(peerId);
    if (conn != null) {
      await conn.close();
      _disconnectedController.add(peerId);
      _log.debug('Connection removed: $peerId');
    }
  }

  // ─── Lookup ───────────────────────────────────────────────────────────────

  /// Returns the [Connection] for [peerId], or `null` if not found.
  Connection? get(String peerId) => _connections[peerId];

  /// Returns `true` if there is an active (non-closed) connection to [peerId].
  bool has(String peerId) {
    final conn = _connections[peerId];
    return conn != null && conn.state != ConnectionState.closed;
  }

  /// All peer IDs with active connections.
  Iterable<String> get peerIds => _connections.keys;

  /// All active [Connection]s.
  Iterable<Connection> get all => _connections.values;

  /// Number of active connections.
  int get count => _connections.length;

  /// Whether no connections exist.
  bool get isEmpty => _connections.isEmpty;

  // ─── Broadcast ────────────────────────────────────────────────────────────

  /// Sends [data] to all connected peers.
  ///
  /// Errors from individual sends are swallowed so one bad peer cannot
  /// prevent delivery to the others.
  Future<void> broadcast(Map<String, dynamic> data) async {
    final futures = _connections.values
        .where((c) => c.isConnected)
        .map((c) => c.send(data).catchError((_) {}));
    await Future.wait(futures);
  }

  /// Sends [data] to the subset of peers identified by [peerIds].
  Future<void> sendToMany(
    Iterable<String> peerIds,
    Map<String, dynamic> data,
  ) async {
    final futures = peerIds
        .map((id) => _connections[id])
        .whereType<Connection>()
        .where((c) => c.isConnected)
        .map((c) => c.send(data).catchError((_) {}));
    await Future.wait(futures);
  }

  // ─── Teardown ────────────────────────────────────────────────────────────

  /// Closes all connections and disposes the manager.
  Future<void> closeAll() async {
    final futures = _connections.values.map((c) => c.close());
    await Future.wait(futures);
    _connections.clear();
    _connectedController.close();
    _disconnectedController.close();
  }

  // ─── Private ─────────────────────────────────────────────────────────────

  void _remove(String peerId) {
    if (_connections.remove(peerId) != null) {
      _disconnectedController.add(peerId);
      _log.debug('Auto-removed closed connection: $peerId');
    }
  }
}
