/// The main entry point of the p2p_dart library.
library;

import 'dart:async';
import 'dart:convert';

import '../core/channel_manager.dart';
import '../core/connection.dart';
import '../core/enums.dart';
import '../core/exceptions.dart';
import '../core/p2p_config.dart';
import '../core/peer_info.dart';
import '../dht/dht_network.dart';
import '../events/event_bus.dart';
import '../events/events.dart';
import '../networking/message.dart';
import '../networking/message_handler.dart';
import '../utils/logger.dart';
import '../webrtc/data_channel_wrapper.dart';
import '../webrtc/webrtc_manager.dart';

// ─── P2P Node ────────────────────────────────────────────────────────────────

/// The central P2P node.
///
/// A [P2PNode] is simultaneously a **client** (it initiates connections to
/// other peers) and a **server** (it accepts incoming connections from others).
///
/// ## Lifecycle
///
/// 1. Construct a [P2PNode] with a [P2PConfig].
/// 2. Call [initialize] — this starts the DHT, WebRTC subsystem, and
///    bootstrapping.
/// 3. Use [connect], [send], [broadcast] to interact with the network.
/// 4. Listen to [eventBus] for real-time events.
/// 5. Call [stop] to cleanly shut down.
///
/// ## Example
///
/// ```dart
/// final node = P2PNode(config: P2PConfig(
///   bootstrapPeers: ['12D3KooW...'],
/// ));
///
/// await node.initialize();
///
/// node.eventBus.on<MessageReceivedEvent>((e) {
///   print('${e.senderId}: ${e.data}');
/// });
///
/// await node.connect('12D3KooWRemote...');
/// await node.send('12D3KooWRemote...', {'hello': 'world'});
/// ```
class P2PNode {
  // ─── Config & Identity ─────────────────────────────────────────────────────

  /// Configuration for this node.
  final P2PConfig config;

  /// This node's unique 160-bit Kademlia peer ID (40-char hex).
  late final String peerId;

  // ─── Subsystems ────────────────────────────────────────────────────────────

  /// The distributed hash table network.
  late final DHTNetwork dhtNetwork;

  /// The WebRTC connection manager.
  late final WebRTCManager webrtcManager;

  /// The connection registry.
  late final ChannelManager channelManager;

  /// The application-level event bus.
  final EventBus eventBus = EventBus();

  /// The global inbound message handler / middleware pipeline.
  final MessageHandler messageHandler = MessageHandler();

  /// The node logger.
  late final P2PLogger _log;

  // ─── State ─────────────────────────────────────────────────────────────────

  NodeStatus _status = NodeStatus.uninitialized;

  /// Current operational status of this node.
  NodeStatus get status => _status;

  /// Whether the node is fully online and operational.
  bool get isOnline => _status == NodeStatus.online;

  // ─── Streams ───────────────────────────────────────────────────────────────

  final StreamController<NodeStatus> _statusController =
      StreamController.broadcast();

  /// Stream of [NodeStatus] changes.
  Stream<NodeStatus> get onStatusChange => _statusController.stream;

  // ─── Constructor ───────────────────────────────────────────────────────────

  /// Creates a [P2PNode] with the supplied [config].
  ///
  /// Does **not** start the node; call [initialize] to do that.
  P2PNode({P2PConfig? config}) : config = config ?? P2PConfig() {
    this.config.validate();
    _log = P2PLogger(
      'P2PNode',
      verbose: this.config.logging.verbose,
      onLog: this.config.logging.onLog,
    );
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  /// Initialises and starts the node.
  ///
  /// Throws [InitializationException] if called on an already-running node.
  Future<void> initialize() async {
    if (_status != NodeStatus.uninitialized) {
      throw InitializationException(
        'Node is already initialised (status: $_status)',
      );
    }

    _setStatus(NodeStatus.bootstrapping);
    _log.info('Initialising node…');

    // 1. Resolve or generate peer ID.
    peerId = config.peerId ?? _generatePeerId();
    _log.info('Peer ID: $peerId');

    // 2. Create subsystems.
    dhtNetwork = DHTNetwork(
      localId: peerId,
      config: config.dht,
      eventBus: eventBus,
      logger: _log,
    );

    webrtcManager = WebRTCManager(
      localPeerId: peerId,
      config: config.webrtc,
      eventBus: eventBus,
      logger: _log,
    );

    channelManager = ChannelManager(
      maxConnections: config.performance.maxConnections,
      logger: _log,
    );

    // 3. Wire WebRTC signalling through DHT.
    webrtcManager.onSignalReady = _forwardSignal;

    // 4. Wire DHT RPC transport through active connections.
    dhtNetwork.setRpcTransport(_dhtRpcTransport);

    // 5. Start subsystems.
    await dhtNetwork.start();
    await webrtcManager.initialize();

    // 6. Register internal message handlers.
    _registerInternalHandlers();

    // 7. Subscribe to WebRTC events.
    _subscribeToWebRtcEvents();

    // 8. Bootstrap into the DHT network.
    await _bootstrap();

    _setStatus(NodeStatus.online);
    eventBus.emit(NodeStartedEvent(peerId: peerId));
    _log.info('Node online. Peer ID: $peerId');
  }

  /// Stops the node, closing all connections and DHT.
  Future<void> stop() async {
    if (_status == NodeStatus.offline || _status == NodeStatus.stopping) return;

    _setStatus(NodeStatus.stopping);
    _log.info('Stopping node…');

    // Notify peers.
    await channelManager.broadcast({'type': 'goodbye', 'from': peerId});

    // Close all connections.
    await channelManager.closeAll();

    // Stop subsystems.
    await webrtcManager.dispose();
    await dhtNetwork.stop();

    _setStatus(NodeStatus.offline);
    eventBus.emit(NodeStoppedEvent(peerId: peerId));
    _statusController.close();
    _log.info('Node stopped.');
  }

  // ─── Connectivity ─────────────────────────────────────────────────────────

  /// Connects to the peer identified by [remotePeerId].
  ///
  /// - If a connection already exists, returns it immediately.
  /// - Performs a DHT lookup to find the peer's [PeerInfo].
  /// - Initiates a WebRTC offer/answer exchange.
  ///
  /// Throws [PeerNotFoundException] if the peer cannot be located.
  /// Throws [ConnectionTimeoutException] if the handshake times out.
  Future<Connection> connect(String remotePeerId) async {
    _assertOnline();

    if (remotePeerId == peerId) {
      throw SelfConnectionException(peerId);
    }

    // Return existing connection if healthy.
    final existing = channelManager.get(remotePeerId);
    if (existing != null && existing.isConnected) {
      return existing;
    }

    _log.debug('Connecting to $remotePeerId…');

    // Locate the peer.
    final peerInfo = await _findPeer(remotePeerId);

    // Initiate WebRTC offer.
    final channel = await webrtcManager.createOffer(peerInfo);

    // Wrap in a Connection and register.
    final connection = _buildConnection(peerInfo, channel);
    channelManager.add(connection);

    return connection;
  }

  /// Returns `true` if there is an active connection to [remotePeerId].
  bool isConnectedTo(String remotePeerId) =>
      channelManager.has(remotePeerId);

  /// Returns the [Connection] to [remotePeerId], or `null`.
  Connection? connectionTo(String remotePeerId) =>
      channelManager.get(remotePeerId);

  /// Disconnects from [remotePeerId].
  Future<void> disconnect(String remotePeerId) =>
      channelManager.remove(remotePeerId);

  // ─── Messaging ────────────────────────────────────────────────────────────

  /// Sends [data] to the peer identified by [targetPeerId].
  ///
  /// Throws [ConnectionClosedException] if no active connection exists.
  Future<void> send(String targetPeerId, Map<String, dynamic> data) async {
    _assertOnline();
    final connection = channelManager.get(targetPeerId);
    if (connection == null || !connection.isConnected) {
      throw ConnectionClosedException(targetPeerId);
    }
    await connection.send(data);
  }

  /// Sends [text] to [targetPeerId].
  Future<void> sendText(String targetPeerId, String text) async {
    _assertOnline();
    final connection = channelManager.get(targetPeerId);
    if (connection == null || !connection.isConnected) {
      throw ConnectionClosedException(targetPeerId);
    }
    await connection.sendText(text);
  }

  /// Broadcasts [data] to all currently connected peers.
  Future<void> broadcast(Map<String, dynamic> data) async {
    _assertOnline();
    await channelManager.broadcast(data);
  }

  /// Sends [data] to only the [peerIds] subset.
  Future<void> sendToMany(
    Iterable<String> peerIds,
    Map<String, dynamic> data,
  ) async {
    _assertOnline();
    await channelManager.sendToMany(peerIds, data);
  }

  // ─── DHT ─────────────────────────────────────────────────────────────────

  /// Stores [value] at [key] in the distributed hash table.
  Future<void> dhtPut(String key, String value) async {
    _assertOnline();
    await dhtNetwork.put(key, value);
  }

  /// Retrieves the value for [key] from the DHT.
  Future<String?> dhtGet(String key) async {
    _assertOnline();
    return dhtNetwork.get(key);
  }

  // ─── Peer Discovery ───────────────────────────────────────────────────────

  /// Returns all peer IDs known to the local routing table.
  List<String> get knownPeers =>
      dhtNetwork.closestKnown(peerId, count: 1000).map((p) => p.peerId).toList();

  /// Returns all currently connected peer IDs.
  Iterable<String> get connectedPeerIds => channelManager.peerIds;

  /// Total number of active connections.
  int get connectionCount => channelManager.count;

  // ─── Private: Bootstrapping ───────────────────────────────────────────────

  Future<void> _bootstrap() async {
    final seeds = config.dht.bootstrapPeers;
    if (seeds.isEmpty) {
      _log.info('No bootstrap peers configured — starting isolated node.');
      return;
    }

    final seedInfos = seeds
        .map((id) => PeerInfo(peerId: id))
        .toList();

    await dhtNetwork.bootstrap(seedInfos);
    _log.info('Bootstrapped with ${seeds.length} seed peers.');
  }

  // ─── Private: Peer Finding ───────────────────────────────────────────────

  Future<PeerInfo> _findPeer(String remotePeerId) async {
    final result = await dhtNetwork.findPeer(remotePeerId);
    if (!result.found) {
      throw PeerNotFoundException(remotePeerId);
    }
    return result.peer!;
  }

  // ─── Private: WebRTC Events ──────────────────────────────────────────────

  void _subscribeToWebRtcEvents() {
    eventBus.on<PeerConnectedEvent>((event) {
      _log.info('WebRTC connected: ${event.peerId}');

      final peerInfo = dhtNetwork
              .closestKnown(event.peerId, count: 1)
              .firstOrNull ??
          PeerInfo(peerId: event.peerId);

      final connection = _buildConnection(peerInfo, event.channel);

      // Only add if not already tracked.
      if (!channelManager.has(event.peerId)) {
        channelManager.add(connection);
      }
    });

    eventBus.on<PeerDisconnectedEvent>((event) {
      _log.info('WebRTC disconnected: ${event.peerId}');
      channelManager.remove(event.peerId).ignore();
      eventBus.emit(
        PeerLeftEvent(peerId: event.peerId, reason: event.reason),
      );
    });
  }

  Connection _buildConnection(PeerInfo peerInfo, DataChannelWrapper channel) {
    final conn = Connection(
      localPeerId: peerId,
      remotePeerInfo: peerInfo,
      channel: channel,
      heartbeatInterval: config.performance.heartbeatInterval,
      logger: _log,
    );

    // Wire inbound DATA messages → application EventBus.
    conn.onData.listen((msg) {
      final data = msg.payload ?? {};
      eventBus.emit(MessageReceivedEvent(
        senderId: msg.senderId,
        data: data,
        rawMessage: msg,
      ));
      messageHandler.dispatch(msg);
    });

    conn.onStateChange.listen((state) {
      if (state == ConnectionState.closed) {
        eventBus.emit(
          PeerLeftEvent(peerId: peerInfo.peerId, reason: 'Connection closed'),
        );
        dhtNetwork.recordFailure(peerInfo.peerId);
      }
    });

    // Add peer to DHT routing table.
    dhtNetwork.addPeer(peerInfo);

    return conn;
  }

  // ─── Private: Signalling Forwarding ─────────────────────────────────────

  Future<void> _forwardSignal(
    String targetPeerId,
    Map<String, dynamic> signal,
  ) async {
    // Try to forward via an existing data channel.
    final connection = channelManager.get(targetPeerId);
    if (connection != null && connection.isConnected) {
      await connection.send({
        'type': 'webrtc_signal',
        'from': peerId,
        'signal': signal,
      });
      return;
    }

    // Otherwise store in DHT for the target to pick up (rendezvous pattern).
    final key = 'signal:$targetPeerId:$peerId';
    await dhtNetwork.put(key, jsonEncode(signal));
    _log.debug('Stored WebRTC signal in DHT for $targetPeerId');
  }

  // ─── Private: DHT RPC Transport ──────────────────────────────────────────

  Future<Map<String, dynamic>> _dhtRpcTransport(
    String targetPeerId,
    Map<String, dynamic> rpc,
  ) async {
    final connection = channelManager.get(targetPeerId);
    if (connection == null || !connection.isConnected) {
      throw DHTException('No connection to $targetPeerId for DHT RPC');
    }

    final correlationId = rpc['correlationId'] as String? ?? _generateCorrId();
    final completer = Completer<Map<String, dynamic>>();

    // Listen for the matching response.
    StreamSubscription? sub;
    sub = connection.onMessage.listen((msg) {
      if (msg.type == MessageType.dhtPong &&
          msg.correlationId == correlationId) {
        sub?.cancel();
        completer.complete(msg.payload ?? {});
      }
    });

    // Send the RPC.
    await connection.send({
      ...rpc,
      'correlationId': correlationId,
      '_dhtRpc': true,
    });

    return completer.future.timeout(
      config.dht.rpcTimeout,
      onTimeout: () {
        sub?.cancel();
        throw DHTException('RPC timeout to $targetPeerId');
      },
    );
  }

  // ─── Private: Internal Message Handlers ─────────────────────────────────

  void _registerInternalHandlers() {
    messageHandler.on(MessageType.dhtPing, _handleDhtPing);
    messageHandler.on(MessageType.dhtFindNode, _handleDhtRpc);
    messageHandler.on(MessageType.dhtFindValue, _handleDhtRpc);
    messageHandler.on(MessageType.dhtStore, _handleDhtRpc);
  }

  Future<void> _handleDhtPing(P2PMessage msg) async {
    final conn = channelManager.get(msg.senderId);
    if (conn == null) return;
    dhtNetwork.touchPeer(msg.senderId);
    await conn.send({
      'type': MessageType.dhtPong.name,
      'correlationId': msg.correlationId,
    });
  }

  Future<void> _handleDhtRpc(P2PMessage msg) async {
    final conn = channelManager.get(msg.senderId);
    if (conn == null) return;

    final payload = msg.payload ?? {};
    final response = dhtNetwork.handleRpc(msg.senderId, payload);

    await conn.send({
      ...response,
      '_dhtRpc': true,
      'correlationId': msg.correlationId,
    });
  }

  // ─── Private: Helpers ────────────────────────────────────────────────────

  String _generatePeerId() {
    // Inline to avoid circular imports at this call-site.
    final bytes = List<int>.generate(20, (_) {
      final now = DateTime.now().microsecondsSinceEpoch;
      return (now ^ (now >> 8)) & 0xFF;
    });
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _generateCorrId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now.toRadixString(36);
  }

  void _setStatus(NodeStatus newStatus) {
    _status = newStatus;
    _statusController.add(newStatus);
  }

  void _assertOnline() {
    if (!isOnline) {
      throw InitializationException(
        'Node is not online (status: $_status). '
        'Call initialize() first.',
      );
    }
  }

  @override
  String toString() =>
      'P2PNode(id: ${isOnline ? peerId.substring(0, 8) : "<unset>"}…, '
      'status: $_status, '
      'connections: ${isOnline ? channelManager.count : 0})';
}
