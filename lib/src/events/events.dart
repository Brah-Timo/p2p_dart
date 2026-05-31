/// All event types emitted on the [EventBus].
library;

import '../core/peer_info.dart';
import '../networking/message.dart';
import '../webrtc/data_channel_wrapper.dart';

// ─── Base ─────────────────────────────────────────────────────────────────────

/// Base class for all p2p_dart events.
abstract class P2PEvent {
  /// When this event was created.
  final DateTime timestamp;

  /// Creates a [P2PEvent].
  P2PEvent() : timestamp = DateTime.now();
}

// ─── Node Events ─────────────────────────────────────────────────────────────

/// Emitted when [P2PNode.initialize] completes.
class NodeStartedEvent extends P2PEvent {
  /// The local peer ID.
  final String peerId;

  /// Creates a [NodeStartedEvent].
  NodeStartedEvent({required this.peerId});
}

/// Emitted when [P2PNode.stop] completes.
class NodeStoppedEvent extends P2PEvent {
  /// The local peer ID.
  final String peerId;

  /// Creates a [NodeStoppedEvent].
  NodeStoppedEvent({required this.peerId});
}

// ─── Peer Events ─────────────────────────────────────────────────────────────

/// Emitted when a new peer connection is fully established.
class PeerConnectedEvent extends P2PEvent {
  /// The remote peer's ID.
  final String peerId;

  /// The data channel for this connection.
  final DataChannelWrapper channel;

  /// Creates a [PeerConnectedEvent].
  PeerConnectedEvent({required this.peerId, required this.channel});
}

/// Emitted when a peer disconnects.
class PeerDisconnectedEvent extends P2PEvent {
  /// The remote peer's ID.
  final String peerId;

  /// Human-readable disconnect reason.
  final String reason;

  /// Creates a [PeerDisconnectedEvent].
  PeerDisconnectedEvent({required this.peerId, this.reason = ''});
}

/// Emitted when a peer intentionally leaves the network.
class PeerLeftEvent extends P2PEvent {
  /// The remote peer's ID.
  final String peerId;

  /// Reason string.
  final String reason;

  /// Creates a [PeerLeftEvent].
  PeerLeftEvent({required this.peerId, this.reason = ''});
}

/// Emitted when a new peer is discovered (but not yet connected).
class PeerDiscoveredEvent extends P2PEvent {
  /// The discovered [PeerInfo].
  final PeerInfo peerInfo;

  /// Creates a [PeerDiscoveredEvent].
  PeerDiscoveredEvent({required this.peerInfo});
}

// ─── Message Events ───────────────────────────────────────────────────────────

/// Emitted when a DATA message is received from a peer.
class MessageReceivedEvent extends P2PEvent {
  /// Sender's peer ID.
  final String senderId;

  /// Decoded application payload.
  final Map<String, dynamic> data;

  /// The original protocol message.
  final P2PMessage rawMessage;

  /// Creates a [MessageReceivedEvent].
  MessageReceivedEvent({
    required this.senderId,
    required this.data,
    required this.rawMessage,
  });
}

/// Emitted when a broadcast message is received.
class BroadcastReceivedEvent extends P2PEvent {
  /// Sender's peer ID.
  final String senderId;

  /// Decoded payload.
  final Map<String, dynamic> data;

  /// Creates a [BroadcastReceivedEvent].
  BroadcastReceivedEvent({required this.senderId, required this.data});
}

// ─── DHT Events ───────────────────────────────────────────────────────────────

/// Emitted once the DHT bootstrapping phase is complete.
class DHTBootstrappedEvent extends P2PEvent {
  /// The local node ID.
  final String nodeId;

  /// Creates a [DHTBootstrappedEvent].
  DHTBootstrappedEvent(this.nodeId);
}

/// Emitted when a DHT key/value record is stored locally.
class DHTValueStoredEvent extends P2PEvent {
  /// The hashed DHT key.
  final String key;

  /// The value stored.
  final String value;

  /// Creates a [DHTValueStoredEvent].
  DHTValueStoredEvent(this.key, this.value);
}

/// Emitted when a DHT lookup returns a value.
class DHTValueFoundEvent extends P2PEvent {
  /// The hashed DHT key.
  final String key;

  /// The found value.
  final String value;

  /// Creates a [DHTValueFoundEvent].
  DHTValueFoundEvent(this.key, this.value);
}

// ─── Error Events ─────────────────────────────────────────────────────────────

/// Emitted when an error occurs that the application may want to handle.
class ErrorEvent extends P2PEvent {
  /// Error description.
  final String message;

  /// Optional underlying exception.
  final Object? error;

  /// Optional stack trace.
  final StackTrace? stackTrace;

  /// Creates an [ErrorEvent].
  ErrorEvent({required this.message, this.error, this.stackTrace});
}
