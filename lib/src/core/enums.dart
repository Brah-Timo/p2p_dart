/// Enumerations used throughout the p2p_dart library.
library;

// ─── Connection State ─────────────────────────────────────────────────────────

/// Lifecycle states of a [Connection].
enum ConnectionState {
  /// Connection object created; handshake not started.
  idle,

  /// SDP offer/answer exchange is in progress.
  connecting,

  /// ICE candidates are being gathered and checked.
  gathering,

  /// ICE connectivity checks are running.
  checking,

  /// WebRTC peer connection is fully established.
  connected,

  /// Connection is temporarily unavailable (may recover).
  disconnected,

  /// Connection has permanently failed.
  failed,

  /// Connection has been cleanly closed.
  closed,
}

// ─── Data Channel State ───────────────────────────────────────────────────────

/// State of an individual [RTCDataChannel]-equivalent abstraction.
enum DataChannelState {
  /// Channel is being negotiated.
  connecting,

  /// Channel is ready to send/receive data.
  open,

  /// Channel is being closed.
  closing,

  /// Channel is fully closed.
  closed,
}

// ─── Message Type ─────────────────────────────────────────────────────────────

/// Classification of protocol messages exchanged on data channels.
enum MessageType {
  /// Application-level text or JSON payload.
  data,

  /// SDP offer — initiates a WebRTC negotiation.
  offer,

  /// SDP answer — responds to an [offer].
  answer,

  /// ICE candidate gathered by the local agent.
  iceCandidate,

  /// Signals that all ICE candidates have been sent.
  iceCandidateComplete,

  /// DHT FIND_NODE RPC.
  dhtFindNode,

  /// DHT FIND_VALUE RPC.
  dhtFindValue,

  /// DHT STORE RPC.
  dhtStore,

  /// DHT PONG response.
  dhtPong,

  /// DHT PING request.
  dhtPing,

  /// Authentication challenge sent to a remote peer.
  authChallenge,

  /// Authentication response answering a [authChallenge].
  authResponse,

  /// Heartbeat keep-alive.
  ping,

  /// Heartbeat reply.
  pong,

  /// Acknowledgement of a reliable message.
  ack,

  /// File transfer chunk.
  fileChunk,

  /// File transfer metadata header.
  fileHeader,

  /// File transfer completion signal.
  fileComplete,

  /// Generic error signal.
  error,

  /// Peer is closing voluntarily.
  goodbye,
}

// ─── Peer Role ────────────────────────────────────────────────────────────────

/// Role a node plays in a WebRTC negotiation.
enum PeerRole {
  /// The node that created and sent the SDP offer.
  offerer,

  /// The node that received the offer and replied with an answer.
  answerer,
}

// ─── Log Level ────────────────────────────────────────────────────────────────

/// Verbosity levels for the built-in logger.
enum LogLevel {
  /// Very detailed diagnostic output.
  trace,

  /// Standard debugging information.
  debug,

  /// Informational operational messages.
  info,

  /// Potential issues that are not yet errors.
  warning,

  /// Recoverable runtime errors.
  error,

  /// Critical failures that abort operation.
  critical,

  /// Logging is disabled entirely.
  off,
}

// ─── Node Status ─────────────────────────────────────────────────────────────

/// High-level operational status of a [P2PNode].
enum NodeStatus {
  /// Node is created but [P2PNode.initialize] has not been called.
  uninitialized,

  /// Node is in the process of bootstrapping into the DHT network.
  bootstrapping,

  /// Node is fully operational and accepting/creating connections.
  online,

  /// Node is shutting down.
  stopping,

  /// Node has stopped.
  offline,
}

// ─── ICE Candidate Type ───────────────────────────────────────────────────────

/// Type of an ICE candidate.
enum IceCandidateType {
  /// Directly reachable host address.
  host,

  /// Server-reflexive (public IP learned via STUN).
  srflx,

  /// Peer-reflexive (learned during connectivity checks).
  prflx,

  /// Relayed address provided by a TURN server.
  relay,
}

// ─── Transport Protocol ───────────────────────────────────────────────────────

/// Underlying transport protocol for ICE candidates.
enum TransportProtocol {
  /// User Datagram Protocol — default for WebRTC.
  udp,

  /// Transmission Control Protocol — used as fallback.
  tcp,
}

// ─── Reliability Mode ─────────────────────────────────────────────────────────

/// Delivery guarantee for a data channel.
enum ReliabilityMode {
  /// Messages delivered reliably and in order (like TCP).
  reliable,

  /// Best-effort delivery, no ordering guarantee (like UDP).
  unreliable,

  /// Messages delivered in order but not necessarily reliably.
  orderedUnreliable,
}

// ─── Discovery Method ─────────────────────────────────────────────────────────

/// Mechanism used to discover a remote peer.
enum DiscoveryMethod {
  /// Peer found in the local DHT routing table.
  dhtRoutingTable,

  /// Peer found by iterative Kademlia lookup.
  dhtLookup,

  /// Peer found via mDNS on the local network segment.
  mDns,

  /// Peer address supplied manually by the application.
  manual,

  /// Peer address found in the in-memory cache.
  cache,
}
