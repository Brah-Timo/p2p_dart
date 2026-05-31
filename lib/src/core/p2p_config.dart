/// Top-level configuration for [P2PNode].
library;

import 'package:p2p_dart/src/dht/dht_config.dart';
import 'package:p2p_dart/src/webrtc/webrtc_config.dart';

// ─── Security Config ─────────────────────────────────────────────────────────

/// Security settings for the node.
class SecurityConfig {
  /// Whether end-to-end encryption is enforced on every connection.
  ///
  /// When `true`, connections that fail the DTLS handshake are immediately
  /// terminated.  Defaults to `true`.
  final bool enforceEncryption;

  /// Whether incoming peers must authenticate with a signed challenge.
  ///
  /// Defaults to `false` (open network).
  final bool requireAuthentication;

  /// How long to wait for an authentication handshake to complete.
  final Duration authTimeout;

  /// Optional pre-shared list of trusted peer IDs.
  ///
  /// When non-empty and [requireAuthentication] is `true`, only peers
  /// whose IDs appear in this list are allowed to connect.
  final List<String> trustedPeers;

  /// Maximum number of failed authentication attempts before banning a peer.
  final int maxAuthFailures;

  /// Creates a [SecurityConfig].
  const SecurityConfig({
    this.enforceEncryption = true,
    this.requireAuthentication = false,
    this.authTimeout = const Duration(seconds: 15),
    this.trustedPeers = const [],
    this.maxAuthFailures = 5,
  });
}

// ─── Performance Config ───────────────────────────────────────────────────────

/// Performance-tuning settings for the node.
class PerformanceConfig {
  /// Maximum number of simultaneous open connections.
  ///
  /// Defaults to `100`.
  final int maxConnections;

  /// Maximum number of messages to buffer per connection before applying
  /// back-pressure.
  ///
  /// Defaults to `1000`.
  final int sendBufferSize;

  /// Maximum size (in bytes) of a single message sent over a data channel.
  ///
  /// Messages larger than this are automatically chunked.
  /// Defaults to `65536` (64 KiB).
  final int maxMessageSize;

  /// Interval between heartbeat pings to detect silently dead connections.
  ///
  /// Defaults to 30 seconds.
  final Duration heartbeatInterval;

  /// How long to wait for a heartbeat reply before declaring the peer dead.
  ///
  /// Defaults to 10 seconds.
  final Duration heartbeatTimeout;

  /// Whether to enable transparent message-level GZIP compression.
  ///
  /// Helps on slow links; adds a small CPU cost.  Defaults to `false`.
  final bool enableCompression;

  /// Minimum payload size (bytes) before compression is applied.
  ///
  /// Ignored when [enableCompression] is `false`.  Defaults to `512`.
  final int compressionThreshold;

  /// Creates a [PerformanceConfig].
  const PerformanceConfig({
    this.maxConnections = 100,
    this.sendBufferSize = 1000,
    this.maxMessageSize = 65536,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.heartbeatTimeout = const Duration(seconds: 10),
    this.enableCompression = false,
    this.compressionThreshold = 512,
  });
}

// ─── Logging Config ───────────────────────────────────────────────────────────

/// Logging preferences for the node.
class LoggingConfig {
  /// Whether verbose diagnostic logging is emitted.
  final bool verbose;

  /// Whether sensitive information (e.g. raw crypto bytes) may appear in logs.
  final bool logSensitiveData;

  /// Optional log output callback.
  ///
  /// When `null`, logs are written to `dart:developer`.
  final void Function(String level, String component, String message)? onLog;

  /// Creates a [LoggingConfig].
  const LoggingConfig({
    this.verbose = false,
    this.logSensitiveData = false,
    this.onLog,
  });
}

// ─── P2P Config ───────────────────────────────────────────────────────────────

/// Master configuration object consumed by [P2PNode].
///
/// Composes [DHTConfig], [WebRTCConfig], [SecurityConfig],
/// [PerformanceConfig], and [LoggingConfig] into a single, validated bundle.
class P2PConfig {
  /// Distributed Hash Table settings.
  final DHTConfig dht;

  /// WebRTC / ICE settings.
  final WebRTCConfig webrtc;

  /// Security settings.
  final SecurityConfig security;

  /// Performance-tuning settings.
  final PerformanceConfig performance;

  /// Logging settings.
  final LoggingConfig logging;

  /// Optional fixed peer ID.
  ///
  /// When `null`, a random 160-bit ID is generated at startup.
  final String? peerId;

  /// Optional human-readable display name advertised to other peers.
  final String? displayName;

  /// Application-level protocol version string.
  ///
  /// Peers running incompatible versions may refuse connections.
  final String protocolVersion;

  /// Creates a [P2PConfig] with sensible defaults.
  P2PConfig({
    DHTConfig? dht,
    WebRTCConfig? webrtc,
    SecurityConfig? security,
    PerformanceConfig? performance,
    LoggingConfig? logging,
    this.peerId,
    this.displayName,
    this.protocolVersion = '1.0.0',
    // Convenience short-hand: bootstrap peers forwarded to DHTConfig.
    List<String>? bootstrapPeers,
  })  : dht = dht ??
            (bootstrapPeers != null
                ? DHTConfig(bootstrapPeers: bootstrapPeers)
                : const DHTConfig()),
        webrtc = webrtc ?? const WebRTCConfig(),
        security = security ?? const SecurityConfig(),
        performance = performance ?? const PerformanceConfig(),
        logging = logging ?? const LoggingConfig();

  /// Validates all sub-configs and throws [ConfigurationException] on error.
  void validate() {
    if (peerId != null && peerId!.length != 40) {
      throw ArgumentError(
        'peerId must be exactly 40 hex characters (160-bit Kademlia key)',
      );
    }
    dht.validate();
    webrtc.validate();
  }

  @override
  String toString() =>
      'P2PConfig(protocol: $protocolVersion, '
      'bootstrap: ${dht.bootstrapPeers.length} peers, '
      'security: enforceEncryption=${security.enforceEncryption})';
}
