/// WebRTC configuration.
library;

import '../core/enums.dart';

// ─── TURN Server Config ───────────────────────────────────────────────────────

/// Credentials for a TURN relay server.
class TurnServerConfig {
  /// Hostname or IP of the TURN server.
  final String host;

  /// Port number (default: 3478 for UDP/TCP, 5349 for TLS).
  final int port;

  /// TURN username.
  final String username;

  /// TURN credential (password).
  final String credential;

  /// Whether to use TLS (turns:// instead of turn://).
  final bool useTls;

  /// Creates a [TurnServerConfig].
  const TurnServerConfig({
    required this.host,
    required this.username,
    required this.credential,
    this.port = 3478,
    this.useTls = false,
  });

  /// Returns the TURN URL string.
  String get url =>
      '${useTls ? 'turns' : 'turn'}:$host:$port';

  /// Returns a JSON-serialisable map.
  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'username': username,
        'useTls': useTls,
      };
}

// ─── STUN Server Config ───────────────────────────────────────────────────────

/// Address of a STUN server.
class StunServerConfig {
  /// Hostname or IP.
  final String host;

  /// Port (default 3478).
  final int port;

  /// Creates a [StunServerConfig].
  const StunServerConfig(this.host, {this.port = 3478});

  /// Returns the STUN URL string.
  String get url => 'stun:$host:$port';
}

// ─── DataChannel Config ───────────────────────────────────────────────────────

/// Options for creating a WebRTC DataChannel.
class DataChannelConfig {
  /// Channel label (name).
  final String label;

  /// Whether messages are delivered in order.
  final bool ordered;

  /// Max retransmissions (unreliable if > 0 and no maxRetransmitTime).
  final int? maxRetransmits;

  /// Max time (ms) to retransmit an unacknowledged message.
  final int? maxRetransmitTime;

  /// Channel ID for pre-negotiation.
  final int? id;

  /// Delivery guarantee.
  final ReliabilityMode reliability;

  /// Creates a [DataChannelConfig].
  const DataChannelConfig({
    this.label = 'p2p-main',
    this.ordered = true,
    this.maxRetransmits,
    this.maxRetransmitTime,
    this.id,
    this.reliability = ReliabilityMode.reliable,
  });

  /// Returns an *unreliable*, *unordered* channel config — good for real-time
  /// gaming data where freshness matters more than completeness.
  factory DataChannelConfig.unreliable({String label = 'p2p-unreliable'}) =>
      DataChannelConfig(
        label: label,
        ordered: false,
        maxRetransmits: 0,
        reliability: ReliabilityMode.unreliable,
      );

  /// Returns a reliable, *ordered* config (default).
  factory DataChannelConfig.reliable({String label = 'p2p-reliable'}) =>
      const DataChannelConfig();
}

// ─── WebRTC Config ────────────────────────────────────────────────────────────

/// Full WebRTC and ICE configuration for [WebRTCManager].
class WebRTCConfig {
  /// STUN servers to use for reflexive address discovery.
  ///
  /// Defaults to Google's public STUN servers.
  final List<StunServerConfig> stunServers;

  /// TURN relay servers to use as a last resort.
  ///
  /// Defaults to an empty list (no relaying — direct only).
  final List<TurnServerConfig> turnServers;

  /// Default data-channel options.
  final DataChannelConfig defaultChannel;

  /// How long to wait for the ICE gathering phase to complete.
  ///
  /// Defaults to 10 seconds.
  final Duration iceGatheringTimeout;

  /// How long to wait for the peer connection to reach "connected" state.
  ///
  /// Defaults to 30 seconds.
  final Duration connectionTimeout;

  /// Maximum number of ICE candidates to gather before forcing completion.
  final int maxIceCandidates;

  /// Whether to include TCP candidates in addition to UDP.
  ///
  /// Defaults to `false` (UDP only is faster).
  final bool enableTcpCandidates;

  /// Whether to enable IPv6 candidates.
  ///
  /// Defaults to `false`.
  final bool enableIpv6;

  /// Whether to allow mDNS (link-local) candidates.
  ///
  /// Useful for LAN-only scenarios.  Defaults to `true`.
  final bool enableMdns;

  /// SDP bundle policy.
  ///
  /// `'max-bundle'` (default) bundles all media/data on a single ICE
  /// component.
  final String bundlePolicy;

  /// RTCP multiplexing policy (`'require'` by default).
  final String rtcpMuxPolicy;

  /// Creates a [WebRTCConfig].
  const WebRTCConfig({
    this.stunServers = const [
      StunServerConfig('stun.l.google.com'),
      StunServerConfig('stun1.l.google.com'),
      StunServerConfig('stun2.l.google.com'),
      StunServerConfig('stun3.l.google.com'),
    ],
    this.turnServers = const [],
    this.defaultChannel = const DataChannelConfig(),
    this.iceGatheringTimeout = const Duration(seconds: 10),
    this.connectionTimeout = const Duration(seconds: 30),
    this.maxIceCandidates = 50,
    this.enableTcpCandidates = false,
    this.enableIpv6 = false,
    this.enableMdns = true,
    this.bundlePolicy = 'max-bundle',
    this.rtcpMuxPolicy = 'require',
  });

  /// Validates configuration constraints.
  void validate() {
    if (stunServers.isEmpty && turnServers.isEmpty) {
      // Allow, but warn — NAT traversal will be limited.
    }
    assert(
      iceGatheringTimeout.inSeconds > 0,
      'iceGatheringTimeout must be positive',
    );
    assert(
      connectionTimeout.inSeconds > 0,
      'connectionTimeout must be positive',
    );
  }

  /// Converts to a flat ICE-servers list for `RTCConfiguration`.
  List<Map<String, dynamic>> toIceServers() {
    final servers = <Map<String, dynamic>>[];

    for (final stun in stunServers) {
      servers.add({'urls': stun.url});
    }

    for (final turn in turnServers) {
      servers.add({
        'urls': turn.url,
        'username': turn.username,
        'credential': turn.credential,
      });
    }

    return servers;
  }

  @override
  String toString() =>
      'WebRTCConfig(stun: ${stunServers.length}, '
      'turn: ${turnServers.length})';
}
