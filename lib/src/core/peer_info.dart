/// Immutable value object describing a peer on the network.
library;

import 'dart:typed_data';

import '../core/enums.dart';

// ─── ICE Candidate ────────────────────────────────────────────────────────────

/// A single ICE connectivity candidate.
class IceCandidate {
  /// Raw SDP candidate line, e.g.
  /// `"candidate:0 1 udp 2130706431 192.168.1.5 5004 typ host"`.
  final String candidate;

  /// SDP media-line index this candidate belongs to.
  final int sdpMediaLineIndex;

  /// SDP media identifier.
  final String sdpMid;

  /// Parsed candidate type.
  final IceCandidateType type;

  /// Transport protocol for this candidate.
  final TransportProtocol protocol;

  /// IP address (may be IPv4 or IPv6).
  final String address;

  /// Port number.
  final int port;

  /// ICE priority value (higher is better).
  final int priority;

  /// Foundation string (used for redundancy elimination).
  final String foundation;

  /// Creates an [IceCandidate].
  const IceCandidate({
    required this.candidate,
    required this.sdpMediaLineIndex,
    required this.sdpMid,
    required this.type,
    required this.protocol,
    required this.address,
    required this.port,
    required this.priority,
    required this.foundation,
  });

  /// Parses a raw SDP candidate string into an [IceCandidate].
  factory IceCandidate.fromSdp(
    String sdpLine, {
    required int sdpMediaLineIndex,
    required String sdpMid,
  }) {
    // Format: candidate:<foundation> <component> <protocol> <priority>
    //          <address> <port> typ <type> [raddr <addr> rport <port>]
    final parts = sdpLine.replaceFirst('candidate:', '').split(' ');

    final foundation = parts[0];
    final protocol = parts[2].toLowerCase() == 'udp'
        ? TransportProtocol.udp
        : TransportProtocol.tcp;
    final priority = int.tryParse(parts[3]) ?? 0;
    final address = parts[4];
    final port = int.tryParse(parts[5]) ?? 0;
    final typeStr = parts.length > 7 ? parts[7] : 'host';

    final type = switch (typeStr) {
      'srflx' => IceCandidateType.srflx,
      'prflx' => IceCandidateType.prflx,
      'relay' => IceCandidateType.relay,
      _ => IceCandidateType.host,
    };

    return IceCandidate(
      candidate: sdpLine,
      sdpMediaLineIndex: sdpMediaLineIndex,
      sdpMid: sdpMid,
      type: type,
      protocol: protocol,
      address: address,
      port: port,
      priority: priority,
      foundation: foundation,
    );
  }

  /// Converts back to a raw SDP candidate string.
  String toSdpLine() => candidate;

  /// Returns a JSON-serialisable map.
  Map<String, dynamic> toJson() => {
        'candidate': candidate,
        'sdpMediaLineIndex': sdpMediaLineIndex,
        'sdpMid': sdpMid,
      };

  /// Reconstructs from a JSON map.
  factory IceCandidate.fromJson(Map<String, dynamic> json) =>
      IceCandidate.fromSdp(
        json['candidate'] as String,
        sdpMediaLineIndex: json['sdpMediaLineIndex'] as int,
        sdpMid: json['sdpMid'] as String,
      );

  @override
  String toString() => 'IceCandidate(type: $type, $address:$port)';

  @override
  bool operator ==(Object other) =>
      other is IceCandidate && other.candidate == candidate;

  @override
  int get hashCode => candidate.hashCode;
}

// ─── Peer Address ─────────────────────────────────────────────────────────────

/// A reachable address for a peer (IP + port combination).
class PeerAddress {
  /// IP address or hostname.
  final String host;

  /// Port number.
  final int port;

  /// Whether this is a loopback or LAN-local address.
  final bool isLocal;

  /// Creates a [PeerAddress].
  const PeerAddress({
    required this.host,
    required this.port,
    this.isLocal = false,
  });

  /// Returns a JSON-serialisable map.
  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'isLocal': isLocal,
      };

  /// Reconstructs from a JSON map.
  factory PeerAddress.fromJson(Map<String, dynamic> json) => PeerAddress(
        host: json['host'] as String,
        port: json['port'] as int,
        isLocal: (json['isLocal'] as bool?) ?? false,
      );

  @override
  String toString() => '$host:$port';

  @override
  bool operator ==(Object other) =>
      other is PeerAddress && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

// ─── Peer Info ────────────────────────────────────────────────────────────────

/// Immutable descriptor for a remote peer.
///
/// Carries everything needed to initiate or accept a connection:
/// - a unique [peerId] (160-bit Kademlia key encoded as hex)
/// - known network [addresses]
/// - gathered [iceCandidates]
/// - the peer's [publicKeyBytes] for signature verification
/// - a [lastSeen] timestamp
class PeerInfo {
  /// Globally unique identifier — 40-character hex string (160 bits).
  final String peerId;

  /// Known reachable addresses for this peer.
  final List<PeerAddress> addresses;

  /// Gathered ICE candidates.
  final List<IceCandidate> iceCandidates;

  /// Raw bytes of the peer's Ed25519 / RSA public key.
  final Uint8List? publicKeyBytes;

  /// When this info was last refreshed.
  final DateTime lastSeen;

  /// Optional human-readable alias (e.g. username).
  final String? displayName;

  /// Metadata bag for application-specific extensions.
  final Map<String, dynamic> metadata;

  /// Protocol version advertised by this peer.
  final String protocolVersion;

  /// Creates a [PeerInfo].
  PeerInfo({
    required this.peerId,
    List<PeerAddress>? addresses,
    List<IceCandidate>? iceCandidates,
    this.publicKeyBytes,
    DateTime? lastSeen,
    this.displayName,
    Map<String, dynamic>? metadata,
    this.protocolVersion = '1.0.0',
  })  : addresses = addresses ?? const [],
        iceCandidates = iceCandidates ?? const [],
        lastSeen = lastSeen ?? DateTime.now(),
        metadata = metadata ?? const {};

  /// Returns a copy with updated fields.
  PeerInfo copyWith({
    List<PeerAddress>? addresses,
    List<IceCandidate>? iceCandidates,
    Uint8List? publicKeyBytes,
    DateTime? lastSeen,
    String? displayName,
    Map<String, dynamic>? metadata,
    String? protocolVersion,
  }) =>
      PeerInfo(
        peerId: peerId,
        addresses: addresses ?? this.addresses,
        iceCandidates: iceCandidates ?? this.iceCandidates,
        publicKeyBytes: publicKeyBytes ?? this.publicKeyBytes,
        lastSeen: lastSeen ?? this.lastSeen,
        displayName: displayName ?? this.displayName,
        metadata: metadata ?? this.metadata,
        protocolVersion: protocolVersion ?? this.protocolVersion,
      );

  /// Returns a JSON-serialisable map.
  Map<String, dynamic> toJson() => {
        'peerId': peerId,
        'addresses': addresses.map((a) => a.toJson()).toList(),
        'iceCandidates': iceCandidates.map((c) => c.toJson()).toList(),
        'lastSeen': lastSeen.toIso8601String(),
        if (displayName != null) 'displayName': displayName,
        'metadata': metadata,
        'protocolVersion': protocolVersion,
      };

  /// Reconstructs from a JSON map.
  factory PeerInfo.fromJson(Map<String, dynamic> json) => PeerInfo(
        peerId: json['peerId'] as String,
        addresses: (json['addresses'] as List<dynamic>?)
                ?.map((a) => PeerAddress.fromJson(a as Map<String, dynamic>))
                .toList() ??
            [],
        iceCandidates: (json['iceCandidates'] as List<dynamic>?)
                ?.map((c) => IceCandidate.fromJson(c as Map<String, dynamic>))
                .toList() ??
            [],
        lastSeen: json['lastSeen'] != null
            ? DateTime.parse(json['lastSeen'] as String)
            : null,
        displayName: json['displayName'] as String?,
        metadata:
            (json['metadata'] as Map<String, dynamic>?) ?? const {},
        protocolVersion:
            (json['protocolVersion'] as String?) ?? '1.0.0',
      );

  /// True if the peer info is considered stale (not seen recently).
  bool get isStale =>
      DateTime.now().difference(lastSeen) > const Duration(minutes: 30);

  /// Abbreviated peer ID for logging.
  String get shortId =>
      peerId.length > 12 ? '${peerId.substring(0, 8)}…' : peerId;

  @override
  String toString() =>
      'PeerInfo(id: $shortId, addresses: ${addresses.length}, '
      'candidates: ${iceCandidates.length})';

  @override
  bool operator ==(Object other) =>
      other is PeerInfo && other.peerId == peerId;

  @override
  int get hashCode => peerId.hashCode;
}
