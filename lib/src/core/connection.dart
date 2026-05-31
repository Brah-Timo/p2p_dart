/// A single peer-to-peer connection between the local node and one remote peer.
library;

import 'dart:async';
import 'dart:typed_data';

import '../core/enums.dart';
import '../core/exceptions.dart';
import '../core/peer_info.dart';
import '../networking/message.dart';
import '../networking/message_handler.dart';
import '../networking/transport.dart';
import '../utils/logger.dart';
import '../webrtc/data_channel_wrapper.dart';

// ─── Connection Stats ────────────────────────────────────────────────────────

/// Snapshot of connection metrics.
class ConnectionStats {
  /// Remote peer ID.
  final String peerId;

  /// Current connection state.
  final ConnectionState state;

  /// Messages sent on this connection.
  final int messagesSent;

  /// Messages received.
  final int messagesReceived;

  /// Total bytes sent.
  final int bytesSent;

  /// Total bytes received.
  final int bytesReceived;

  /// When the connection was established (null if not yet connected).
  final DateTime? connectedAt;

  /// Round-trip time estimate in milliseconds (null if unknown).
  final int? rttMs;

  /// Creates [ConnectionStats].
  const ConnectionStats({
    required this.peerId,
    required this.state,
    required this.messagesSent,
    required this.messagesReceived,
    required this.bytesSent,
    required this.bytesReceived,
    this.connectedAt,
    this.rttMs,
  });

  /// Connection uptime (zero if not connected).
  Duration get uptime =>
      connectedAt != null ? DateTime.now().difference(connectedAt!) : Duration.zero;

  @override
  String toString() =>
      'ConnectionStats(peer: ${peerId.substring(0, 8)}…, '
      'state: $state, '
      'sent: $messagesSent, recv: $messagesReceived, '
      'uptime: ${uptime.inSeconds}s)';
}

// ─── Connection ───────────────────────────────────────────────────────────────

/// Represents an established data connection to a remote peer.
///
/// A [Connection] wraps a [DataChannelWrapper] and provides:
/// - Typed [send] / [sendBinary] methods.
/// - Automatic heartbeat keep-alive.
/// - A [MessageHandler] pipeline for routing inbound messages.
/// - Lifecycle events via [onStateChange].
class Connection {
  // ─── Identity ──────────────────────────────────────────────────────────────

  /// Local peer's ID.
  final String localPeerId;

  /// Remote peer's ID.
  final String remotePeerId;

  /// Remote peer info.
  final PeerInfo remotePeerInfo;

  // ─── Internals ─────────────────────────────────────────────────────────────

  final DataChannelWrapper _channel;
  final TransportLayer _transport;
  final MessageHandler _messageHandler;
  final P2PLogger _log;

  ConnectionState _state = ConnectionState.idle;
  DateTime? _connectedAt;

  // Heartbeat
  Timer? _heartbeatTimer;
  DateTime? _lastPong;
  final Duration _heartbeatInterval;

  // Stats
  int _messagesSent = 0;
  int _messagesReceived = 0;

  // ─── Streams ───────────────────────────────────────────────────────────────

  final StreamController<ConnectionState> _stateController =
      StreamController.broadcast();

  final StreamController<P2PMessage> _messageController =
      StreamController.broadcast();

  /// Stream of connection state changes.
  Stream<ConnectionState> get onStateChange => _stateController.stream;

  /// Raw stream of inbound [P2PMessage]s (all types).
  Stream<P2PMessage> get onMessage => _messageController.stream;

  /// Convenience stream of DATA messages only.
  Stream<P2PMessage> get onData => onMessage.where(
        (m) => m.type == MessageType.data,
      );

  // ─── Constructor ───────────────────────────────────────────────────────────

  /// Creates a [Connection].
  Connection({
    required this.localPeerId,
    required this.remotePeerInfo,
    required DataChannelWrapper channel,
    MessageHandler? messageHandler,
    Duration heartbeatInterval = const Duration(seconds: 30),
    P2PLogger? logger,
  })  : remotePeerId = remotePeerInfo.peerId,
        _channel = channel,
        _transport = TransportLayer(peerId: remotePeerInfo.peerId),
        _messageHandler = messageHandler ?? MessageHandler(),
        _heartbeatInterval = heartbeatInterval,
        _log = logger ?? P2PLogger('Connection[${remotePeerInfo.peerId.substring(0, 8)}]') {
    _init();
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  /// Current state of this connection.
  ConnectionState get state => _state;

  /// Whether the connection is ready to send/receive data.
  bool get isConnected => _state == ConnectionState.connected;

  // ─── Send API ─────────────────────────────────────────────────────────────

  /// Sends a JSON-serialisable [data] map to the remote peer.
  Future<void> send(Map<String, dynamic> data) async {
    _assertConnected();
    final message = P2PMessage.data(localPeerId, data);
    await _sendMessage(message);
  }

  /// Sends a raw text string.
  Future<void> sendText(String text) async {
    _assertConnected();
    final message = P2PMessage.data(localPeerId, {'text': text});
    await _sendMessage(message);
  }

  /// Sends raw [bytes] (auto-encodes as base64 in the message payload).
  Future<void> sendBinary(Uint8List bytes) async {
    _assertConnected();
    final message = P2PMessage(
      type: MessageType.data,
      senderId: localPeerId,
      binaryPayload: bytes,
    );
    await _sendMessage(message);
  }

  /// Registers an inbound message handler for [type].
  void on(MessageType type, TypedMessageHandler handler) {
    _messageHandler.on(type, handler);
  }

  /// Adds global middleware.
  void use(MessageMiddleware middleware) {
    _messageHandler.use(middleware);
  }

  // ─── Close ────────────────────────────────────────────────────────────────

  /// Closes this connection, stopping heartbeats and releasing resources.
  Future<void> close() async {
    if (_state == ConnectionState.closed) return;

    _heartbeatTimer?.cancel();
    _transport.stop();

    // Send goodbye if still usable.
    if (_channel.isOpen) {
      try {
        _channel.sendJson(P2PMessage.goodbye(localPeerId).toJson());
      } catch (_) {}
    }

    await _channel.close();
    _setState(ConnectionState.closed);
    _log.info('Connection closed.');
  }

  // ─── Stats ────────────────────────────────────────────────────────────────

  /// Returns a snapshot of connection metrics.
  ConnectionStats stats() => ConnectionStats(
        peerId: remotePeerId,
        state: _state,
        messagesSent: _messagesSent,
        messagesReceived: _messagesReceived,
        bytesSent: _channel.bytesSent,
        bytesReceived: _channel.bytesReceived,
        connectedAt: _connectedAt,
        rttMs: _lastPong != null
            ? DateTime.now().difference(_lastPong!).inMilliseconds
            : null,
      );

  // ─── Private: Initialisation ─────────────────────────────────────────────

  void _init() {
    // Wire transport → channel.
    _transport.onSendBytes = (bytes) {
      if (_channel.isOpen) {
        _channel.sendBinary(bytes);
      }
    };
    _transport.start();

    // Wire channel → transport (inbound path).
    _channel.onMessage.listen(_onChannelMessage);
    _channel.onStateChange.listen(_onChannelStateChange);

    // Wire transport inbound → message handler.
    _transport.inbound.listen(_onTransportMessage);

    // Register internal protocol handlers.
    _messageHandler.on(MessageType.ping, _handlePing);
    _messageHandler.on(MessageType.pong, _handlePong);
    _messageHandler.on(MessageType.goodbye, _handleGoodbye);

    // If channel is already open, transition immediately.
    if (_channel.isOpen) {
      _onChannelStateChange(DataChannelState.open);
    }
  }

  void _onChannelStateChange(DataChannelState channelState) {
    switch (channelState) {
      case DataChannelState.open:
        _setState(ConnectionState.connected);
        _connectedAt = DateTime.now();
        _startHeartbeat();
        _log.info('Connection established with $remotePeerId');
      case DataChannelState.closing:
        _setState(ConnectionState.disconnected);
      case DataChannelState.closed:
        _setState(ConnectionState.closed);
        _heartbeatTimer?.cancel();
      case DataChannelState.connecting:
        _setState(ConnectionState.connecting);
    }
  }

  void _onChannelMessage(DataChannelMessage message) {
    final bytes = message.isBinary
        ? message.binary!
        : Uint8List.fromList(message.text!.codeUnits);
    _transport.receive(bytes);
  }

  void _onTransportMessage(P2PMessage message) {
    _messagesReceived++;
    _messageController.add(message);
    _messageHandler.dispatch(message);
  }

  // ─── Private: Heartbeat ──────────────────────────────────────────────────

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendPing());
  }

  void _sendPing() {
    if (!isConnected) return;
    final ping = P2PMessage.ping(localPeerId);
    _sendMessage(ping).catchError((_) {});
  }

  Future<void> _handlePing(P2PMessage message) async {
    final pong = P2PMessage.pong(localPeerId, message.correlationId);
    await _sendMessage(pong);
  }

  Future<void> _handlePong(P2PMessage message) async {
    _lastPong = DateTime.now();
    _log.debug('Pong from $remotePeerId');
  }

  Future<void> _handleGoodbye(P2PMessage message) async {
    _log.info('Peer $remotePeerId sent goodbye.');
    await close();
  }

  // ─── Private: Helpers ────────────────────────────────────────────────────

  Future<void> _sendMessage(P2PMessage message) async {
    if (!_channel.isOpen) {
      throw ConnectionClosedException(remotePeerId);
    }
    _channel.sendJson(message.toJson());
    _messagesSent++;
  }

  void _setState(ConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }

  void _assertConnected() {
    if (!isConnected) {
      throw ConnectionClosedException(remotePeerId);
    }
  }

  @override
  String toString() =>
      'Connection(remote: ${remotePeerId.substring(0, 8)}…, state: $_state)';
}
