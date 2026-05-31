/// Typed exception hierarchy for p2p_dart.
library;

// ─── Base ─────────────────────────────────────────────────────────────────────

/// Root exception class for all p2p_dart errors.
class P2PException implements Exception {
  /// Human-readable description of what went wrong.
  final String message;

  /// Optional underlying cause.
  final Object? cause;

  /// Optional stack trace from the root cause.
  final StackTrace? causeStackTrace;

  /// Creates a [P2PException].
  const P2PException(
    this.message, {
    this.cause,
    this.causeStackTrace,
  });

  @override
  String toString() {
    final buffer = StringBuffer('P2PException: $message');
    if (cause != null) buffer.write('\n  Caused by: $cause');
    if (causeStackTrace != null) {
      buffer.write('\n  Cause stack trace:\n$causeStackTrace');
    }
    return buffer.toString();
  }
}

// ─── Initialisation ──────────────────────────────────────────────────────────

/// Thrown when [P2PNode.initialize] fails or is called in the wrong state.
class InitializationException extends P2PException {
  /// Creates an [InitializationException].
  const InitializationException(super.message, {super.cause, super.causeStackTrace});

  @override
  String toString() => 'InitializationException: $message';
}

// ─── Connection ───────────────────────────────────────────────────────────────

/// Thrown when a connection attempt fails or is invalid.
class ConnectionException extends P2PException {
  /// The peer ID that was the target of the failed operation.
  final String? peerId;

  /// Creates a [ConnectionException].
  const ConnectionException(
    super.message, {
    this.peerId,
    super.cause,
    super.causeStackTrace,
  });

  @override
  String toString() {
    final id = peerId != null ? ' [peer: $peerId]' : '';
    return 'ConnectionException$id: $message';
  }
}

/// Thrown when attempting to send data on a closed or failed connection.
class ConnectionClosedException extends ConnectionException {
  /// Creates a [ConnectionClosedException].
  const ConnectionClosedException(String peerId)
      : super('Connection to $peerId is closed', peerId: peerId);
}

/// Thrown when connecting to self is attempted.
class SelfConnectionException extends ConnectionException {
  /// Creates a [SelfConnectionException].
  const SelfConnectionException(String peerId)
      : super('Cannot connect to self', peerId: peerId);
}

/// Thrown when a connection attempt times out.
class ConnectionTimeoutException extends ConnectionException {
  /// How long was waited before timing out.
  final Duration timeout;

  /// Creates a [ConnectionTimeoutException].
  ConnectionTimeoutException(String peerId, this.timeout)
      : super(
          'Connection to $peerId timed out after ${timeout.inMilliseconds}ms',
          peerId: peerId,
        );
}

// ─── Peer / Discovery ────────────────────────────────────────────────────────

/// Thrown when a peer cannot be found in the DHT.
class PeerNotFoundException extends P2PException {
  /// The peer ID that was searched for.
  final String peerId;

  /// Creates a [PeerNotFoundException].
  const PeerNotFoundException(this.peerId)
      : super('Peer not found in DHT: $peerId');

  @override
  String toString() => 'PeerNotFoundException: $message';
}

/// Thrown when DHT operations fail.
class DHTException extends P2PException {
  /// Creates a [DHTException].
  const DHTException(super.message, {super.cause, super.causeStackTrace});

  @override
  String toString() => 'DHTException: $message';
}

// ─── WebRTC ──────────────────────────────────────────────────────────────────

/// Thrown when a WebRTC-level operation fails.
class WebRTCException extends P2PException {
  /// Creates a [WebRTCException].
  const WebRTCException(super.message, {super.cause, super.causeStackTrace});

  @override
  String toString() => 'WebRTCException: $message';
}

/// Thrown when SDP negotiation fails.
class SDPException extends WebRTCException {
  /// Creates an [SDPException].
  const SDPException(super.message, {super.cause});

  @override
  String toString() => 'SDPException: $message';
}

/// Thrown when ICE gathering or connectivity checks fail.
class ICEException extends WebRTCException {
  /// Creates an [ICEException].
  const ICEException(super.message, {super.cause});

  @override
  String toString() => 'ICEException: $message';
}

// ─── Security ────────────────────────────────────────────────────────────────

/// Thrown when a cryptographic operation fails.
class CryptoException extends P2PException {
  /// Creates a [CryptoException].
  const CryptoException(super.message, {super.cause, super.causeStackTrace});

  @override
  String toString() => 'CryptoException: $message';
}

/// Thrown when peer authentication fails.
class AuthenticationException extends P2PException {
  /// The peer whose authentication failed.
  final String peerId;

  /// Creates an [AuthenticationException].
  const AuthenticationException(this.peerId, [String detail = ''])
      : super('Authentication failed for peer $peerId. $detail');

  @override
  String toString() => 'AuthenticationException: $message';
}

// ─── Data Channel ─────────────────────────────────────────────────────────────

/// Thrown when a data channel operation fails.
class DataChannelException extends P2PException {
  /// Creates a [DataChannelException].
  const DataChannelException(super.message, {super.cause});

  @override
  String toString() => 'DataChannelException: $message';
}

// ─── Transport ────────────────────────────────────────────────────────────────

/// Thrown when a network send/receive operation fails.
class TransportException extends P2PException {
  /// Creates a [TransportException].
  const TransportException(super.message, {super.cause, super.causeStackTrace});

  @override
  String toString() => 'TransportException: $message';
}

// ─── Serialisation ────────────────────────────────────────────────────────────

/// Thrown when message serialisation or deserialisation fails.
class SerializationException extends P2PException {
  /// Creates a [SerializationException].
  const SerializationException(super.message, {super.cause});

  @override
  String toString() => 'SerializationException: $message';
}

// ─── Configuration ────────────────────────────────────────────────────────────

/// Thrown when configuration values are invalid.
class ConfigurationException extends P2PException {
  /// The configuration field that caused the problem.
  final String? fieldName;

  /// Creates a [ConfigurationException].
  const ConfigurationException(
    super.message, {
    this.fieldName,
    super.cause,
  });

  @override
  String toString() {
    final field = fieldName != null ? ' [field: $fieldName]' : '';
    return 'ConfigurationException$field: $message';
  }
}
