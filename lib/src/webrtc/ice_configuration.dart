/// ICE configuration and candidate management.
library;

import '../core/enums.dart';
import '../core/peer_info.dart';
import 'webrtc_config.dart';

// ─── ICE Configuration ───────────────────────────────────────────────────────

/// Resolved ICE configuration to pass to a peer connection.
class IceConfiguration {
  /// ICE servers list (STUN + TURN).
  final List<Map<String, dynamic>> iceServers;

  /// Bundle policy.
  final String bundlePolicy;

  /// RTCP multiplexing policy.
  final String rtcpMuxPolicy;

  /// ICE transport policy: `'all'` or `'relay'` (relay-only).
  final String iceTransportPolicy;

  /// Creates an [IceConfiguration].
  const IceConfiguration({
    required this.iceServers,
    this.bundlePolicy = 'max-bundle',
    this.rtcpMuxPolicy = 'require',
    this.iceTransportPolicy = 'all',
  });

  /// Builds an [IceConfiguration] from a [WebRTCConfig].
  factory IceConfiguration.from(
    WebRTCConfig config, {
    bool relayOnly = false,
  }) =>
      IceConfiguration(
        iceServers: config.toIceServers(),
        bundlePolicy: config.bundlePolicy,
        rtcpMuxPolicy: config.rtcpMuxPolicy,
        iceTransportPolicy: relayOnly ? 'relay' : 'all',
      );

  /// Returns the raw map expected by a `RTCPeerConnection` constructor.
  Map<String, dynamic> toMap() => {
        'iceServers': iceServers,
        'bundlePolicy': bundlePolicy,
        'rtcpMuxPolicy': rtcpMuxPolicy,
        'iceTransportPolicy': iceTransportPolicy,
      };

  @override
  String toString() =>
      'IceConfiguration(servers: ${iceServers.length}, '
      'policy: $iceTransportPolicy)';
}

// ─── ICE Candidate Pool ───────────────────────────────────────────────────────

/// Collects and ranks ICE candidates for a single peer connection.
class IceCandidatePool {
  final List<IceCandidate> _candidates = [];
  bool _gatheringComplete = false;

  /// Adds a candidate to the pool.
  void add(IceCandidate candidate) {
    if (!_candidates.contains(candidate)) {
      _candidates.add(candidate);
    }
  }

  /// Marks ICE gathering as complete.
  void markComplete() => _gatheringComplete = true;

  /// Whether ICE gathering has completed.
  bool get isComplete => _gatheringComplete;

  /// All gathered candidates.
  List<IceCandidate> get all => List.unmodifiable(_candidates);

  /// Candidates sorted by priority (host > srflx > prflx > relay).
  List<IceCandidate> get sorted {
    final priorityMap = {
      IceCandidateType.host: 0,
      IceCandidateType.srflx: 1,
      IceCandidateType.prflx: 2,
      IceCandidateType.relay: 3,
    };

    return List<IceCandidate>.from(_candidates)
      ..sort((a, b) {
        final pa = priorityMap[a.type] ?? 4;
        final pb = priorityMap[b.type] ?? 4;
        if (pa != pb) return pa.compareTo(pb);
        // Secondary sort by priority field (higher is better).
        return b.priority.compareTo(a.priority);
      });
  }

  /// Host (LAN) candidates only.
  List<IceCandidate> get hostCandidates =>
      _candidates.where((c) => c.type == IceCandidateType.host).toList();

  /// Server-reflexive (STUN) candidates only.
  List<IceCandidate> get srflxCandidates =>
      _candidates.where((c) => c.type == IceCandidateType.srflx).toList();

  /// Relay (TURN) candidates only.
  List<IceCandidate> get relayCandidates =>
      _candidates.where((c) => c.type == IceCandidateType.relay).toList();

  /// Returns the best (highest-priority) candidate, or `null` if empty.
  IceCandidate? get best => sorted.isNotEmpty ? sorted.first : null;

  /// Number of gathered candidates.
  int get length => _candidates.length;

  /// Converts all candidates to a JSON list.
  List<Map<String, dynamic>> toJsonList() =>
      sorted.map((c) => c.toJson()).toList();

  @override
  String toString() =>
      'IceCandidatePool(count: ${_candidates.length}, '
      'complete: $_gatheringComplete)';
}

// ─── ICE State Machine ────────────────────────────────────────────────────────

/// Tracks the ICE negotiation state for a connection.
class IceStateMachine {
  IceCandidateType? _bestLocalType;
  IceCandidateType? _bestRemoteType;

  /// Records the best local candidate type used.
  void setBestLocalType(IceCandidateType type) => _bestLocalType = type;

  /// Records the best remote candidate type used.
  void setBestRemoteType(IceCandidateType type) => _bestRemoteType = type;

  /// The determined path type after ICE completes.
  ///
  /// Returns `null` if ICE has not completed yet.
  IceCandidateType? get pathType {
    if (_bestLocalType == null || _bestRemoteType == null) return null;
    // The effective path is the higher-cost type of the pair.
    if (_bestLocalType == IceCandidateType.relay ||
        _bestRemoteType == IceCandidateType.relay) {
      return IceCandidateType.relay;
    }
    if (_bestLocalType == IceCandidateType.srflx ||
        _bestRemoteType == IceCandidateType.srflx) {
      return IceCandidateType.srflx;
    }
    return IceCandidateType.host;
  }

  /// Human-readable description of the negotiated path.
  String get pathDescription => switch (pathType) {
        IceCandidateType.host => 'Direct LAN',
        IceCandidateType.srflx => 'Direct Internet (NAT traversal)',
        IceCandidateType.relay => 'Relayed via TURN',
        _ => 'Unknown',
      };

  @override
  String toString() => 'IceStateMachine(path: $pathDescription)';
}
