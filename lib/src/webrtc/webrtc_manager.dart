/// WebRTC peer connection manager.
library;

import 'dart:async';
import 'dart:math';

import '../core/exceptions.dart';
import '../core/peer_info.dart';
import '../events/event_bus.dart';
import '../events/events.dart';
import '../utils/logger.dart';
import 'data_channel_wrapper.dart';
import 'webrtc_config.dart';

// ─── SDP Session Description ─────────────────────────────────────────────────

/// Minimal SDP session description.
class SessionDescription {
  /// `'offer'` or `'answer'`.
  final String type;

  /// Raw SDP body.
  final String sdp;

  /// Creates a [SessionDescription].
  const SessionDescription({required this.type, required this.sdp});

  /// Returns a JSON-serialisable map.
  Map<String, dynamic> toJson() => {'type': type, 'sdp': sdp};

  /// Reconstructs from a JSON map.
  factory SessionDescription.fromJson(Map<String, dynamic> json) =>
      SessionDescription(
        type: json['type'] as String,
        sdp: json['sdp'] as String,
      );

  @override
  String toString() => 'SessionDescription(type: $type)';
}

// ─── Pending Offer ────────────────────────────────────────────────────────────

/// Holds the state for an in-progress offer/answer exchange.
class _PendingOffer {
  final String remotePeerId;
  final Completer<DataChannelWrapper> completer;
  SessionDescription? localSdp;
  SessionDescription? remoteSdp;
  final List<IceCandidate> localCandidates = [];
  final List<IceCandidate> remoteCandidates = [];
  final DateTime createdAt = DateTime.now();

  _PendingOffer(this.remotePeerId) : completer = Completer();

  bool get isExpired =>
      DateTime.now().difference(createdAt) > const Duration(seconds: 60);
}

// ─── WebRTC Manager ──────────────────────────────────────────────────────────

/// Manages WebRTC peer connections and data channels.
///
/// Responsibilities:
/// - Creating SDP offers and answers.
/// - Gathering and exchanging ICE candidates.
/// - Maintaining a registry of active [DataChannelWrapper]s.
/// - Routing incoming signalling messages to the right pending offer.
///
/// **Signalling transport** is provided externally: the [P2PNode] calls
/// [handleSignalMessage] when a WebRTC signal arrives from the network,
/// and [WebRTCManager] calls [onSignalReady] when it needs to send one.
class WebRTCManager {
  // ─── Dependencies ──────────────────────────────────────────────────────────

  final String _localPeerId;
  final WebRTCConfig _config;
  final EventBus _eventBus;
  final P2PLogger _log;

  // ─── State ─────────────────────────────────────────────────────────────────

  /// Signalling callback — set by [P2PNode] to forward signals over the DHT.
  Future<void> Function(String targetPeerId, Map<String, dynamic> signal)?
      onSignalReady;

  /// Active data channels, keyed by remote peer ID.
  final Map<String, DataChannelWrapper> _channels = {};

  /// In-flight offer/answer exchanges.
  final Map<String, _PendingOffer> _pendingOffers = {};

  bool _initialized = false;

  // ─── Constructor ───────────────────────────────────────────────────────────

  /// Creates a [WebRTCManager].
  WebRTCManager({
    required String localPeerId,
    required WebRTCConfig config,
    required EventBus eventBus,
    P2PLogger? logger,
  })  : _localPeerId = localPeerId,
        _config = config,
        _eventBus = eventBus,
        _log = logger ?? P2PLogger('WebRTC');

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  /// Initialises the WebRTC subsystem.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _startCleanupTimer();
    _log.info('WebRTCManager ready. Local peer: $_localPeerId');
  }

  /// Disposes all channels and pending offers.
  Future<void> dispose() async {
    for (final channel in _channels.values) {
      await channel.close();
    }
    _channels.clear();
    _pendingOffers.clear();
    _initialized = false;
    _log.info('WebRTCManager disposed.');
  }

  // ─── Connection Initiation ───────────────────────────────────────────────

  /// Creates a WebRTC connection to [remotePeerInfo] by sending an SDP offer.
  ///
  /// Returns a [DataChannelWrapper] once the connection is established.
  Future<DataChannelWrapper> createOffer(PeerInfo remotePeerInfo) async {
    _assertInitialized();
    final peerId = remotePeerInfo.peerId;

    // Reuse existing channel if available.
    if (_channels.containsKey(peerId) && _channels[peerId]!.isOpen) {
      return _channels[peerId]!;
    }

    if (_pendingOffers.containsKey(peerId)) {
      return _pendingOffers[peerId]!.completer.future;
    }

    final pending = _PendingOffer(peerId);
    _pendingOffers[peerId] = pending;

    // Generate a synthetic SDP offer (real impl calls RTCPeerConnection).
    final offer = _generateSyntheticSdp('offer', peerId);
    pending.localSdp = offer;

    // Gather ICE candidates.
    final candidates = await _gatherIceCandidates();
    pending.localCandidates.addAll(candidates);

    // Send offer + candidates to remote peer.
    await _sendSignal(peerId, {
      'type': 'offer',
      'sdp': offer.toJson(),
      'candidates': candidates.map((c) => c.toJson()).toList(),
    });

    _log.debug('Sent SDP offer to $peerId');

    return pending.completer.future.timeout(
      _config.connectionTimeout,
      onTimeout: () {
        _pendingOffers.remove(peerId);
        throw ConnectionTimeoutException(peerId, _config.connectionTimeout);
      },
    );
  }

  // ─── Signal Handling ─────────────────────────────────────────────────────

  /// Processes an incoming WebRTC signal from [senderPeerId].
  Future<void> handleSignalMessage(
    String senderPeerId,
    Map<String, dynamic> signal,
  ) async {
    final type = signal['type'] as String?;

    switch (type) {
      case 'offer':
        await _handleOffer(senderPeerId, signal);
      case 'answer':
        await _handleAnswer(senderPeerId, signal);
      case 'ice_candidate':
        _handleIceCandidate(senderPeerId, signal);
      case 'ice_complete':
        _handleIceComplete(senderPeerId);
      case 'bye':
        await _handleBye(senderPeerId);
      default:
        _log.warning('Unknown signal type: $type from $senderPeerId');
    }
  }

  // ─── Channel Access ──────────────────────────────────────────────────────

  /// Returns the active [DataChannelWrapper] for [peerId], or `null`.
  DataChannelWrapper? getChannel(String peerId) => _channels[peerId];

  /// Returns `true` if there is an open data channel to [peerId].
  bool hasActiveChannel(String peerId) =>
      _channels[peerId]?.isOpen ?? false;

  /// All peer IDs that have open data channels.
  Iterable<String> get connectedPeers =>
      _channels.keys.where((id) => _channels[id]!.isOpen);

  // ─── Closing ─────────────────────────────────────────────────────────────

  /// Closes the data channel to [peerId] and sends a 'bye' signal.
  Future<void> closeChannel(String peerId) async {
    final channel = _channels.remove(peerId);
    if (channel != null) {
      await channel.close();
    }

    try {
      await _sendSignal(peerId, {'type': 'bye'});
    } catch (_) {}

    _log.debug('Closed channel to $peerId');
  }

  // ─── Private: Signal Handlers ────────────────────────────────────────────

  Future<void> _handleOffer(
    String senderPeerId,
    Map<String, dynamic> signal,
  ) async {
    _log.debug('Received SDP offer from $senderPeerId');

    // Generate answer.
    final answer = _generateSyntheticSdp('answer', senderPeerId);
    final localCandidates = await _gatherIceCandidates();

    // Send answer.
    await _sendSignal(senderPeerId, {
      'type': 'answer',
      'sdp': answer.toJson(),
      'candidates': localCandidates.map((c) => c.toJson()).toList(),
    });

    // Create the data channel.
    final channel = _createChannel(senderPeerId);
    channel.markOpen();
    _channels[senderPeerId] = channel;

    _eventBus.emit(PeerConnectedEvent(
      peerId: senderPeerId,
      channel: channel,
    ));

    _log.info('Connection established (answerer) with $senderPeerId');
  }

  Future<void> _handleAnswer(
    String senderPeerId,
    Map<String, dynamic> signal,
  ) async {
    _log.debug('Received SDP answer from $senderPeerId');

    final pending = _pendingOffers[senderPeerId];
    if (pending == null) {
      _log.warning('No pending offer for answer from $senderPeerId');
      return;
    }

    final answer = SessionDescription.fromJson(
      signal['sdp'] as Map<String, dynamic>,
    );
    pending.remoteSdp = answer;

    final remoteCandidates = (signal['candidates'] as List<dynamic>?)
            ?.map((c) => IceCandidate.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [];
    pending.remoteCandidates.addAll(remoteCandidates);

    // Simulate ICE completion and create channel.
    final channel = _createChannel(senderPeerId);
    channel.markOpen();
    _channels[senderPeerId] = channel;
    _pendingOffers.remove(senderPeerId);

    if (!pending.completer.isCompleted) {
      pending.completer.complete(channel);
    }

    _eventBus.emit(PeerConnectedEvent(
      peerId: senderPeerId,
      channel: channel,
    ));

    _log.info('Connection established (offerer) with $senderPeerId');
  }

  void _handleIceCandidate(
    String senderPeerId,
    Map<String, dynamic> signal,
  ) {
    final pending = _pendingOffers[senderPeerId];
    if (pending == null) return;

    final candidate = IceCandidate.fromJson(
      signal['candidate'] as Map<String, dynamic>,
    );
    pending.remoteCandidates.add(candidate);
    _log.debug('Added remote ICE candidate from $senderPeerId: $candidate');
  }

  void _handleIceComplete(String senderPeerId) {
    _log.debug('ICE gathering complete signal from $senderPeerId');
  }

  Future<void> _handleBye(String senderPeerId) async {
    final channel = _channels.remove(senderPeerId);
    if (channel != null) {
      await channel.close();
    }
    _eventBus.emit(PeerDisconnectedEvent(
      peerId: senderPeerId,
      reason: 'Remote peer closed connection',
    ));
    _log.info('Peer $senderPeerId closed the connection.');
  }

  // ─── Private: ICE & SDP Helpers ──────────────────────────────────────────

  Future<List<IceCandidate>> _gatherIceCandidates() async {
    final candidates = <IceCandidate>[];

    // Add a synthetic host candidate (loopback — for testing).
    candidates.add(
      IceCandidate.fromSdp(
        'candidate:0 1 udp 2130706431 127.0.0.1 10000 typ host',
        sdpMediaLineIndex: 0,
        sdpMid: 'data',
      ),
    );

    // Attempt STUN discovery.
    for (final stun in _config.stunServers.take(2)) {
      try {
        // Real implementation queries the STUN server here.
        // We produce a synthetic srflx candidate.
        candidates.add(
          IceCandidate.fromSdp(
            'candidate:1 1 udp 1845494015 1.2.3.4 20000 typ srflx '
            'raddr 192.168.1.1 rport 10001',
            sdpMediaLineIndex: 0,
            sdpMid: 'data',
          ),
        );
        break;
      } catch (e) {
        _log.debug('STUN gather failed for ${stun.host}: $e');
      }
    }

    // Timeout: stop gathering after iceGatheringTimeout.
    return candidates;
  }

  SessionDescription _generateSyntheticSdp(String type, String remotePeerId) {
    final rng = Random.secure();
    final sessionId = rng.nextInt(0xFFFFFF).toString();

    final sdp = '''v=0
o=- $sessionId 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE data
a=msid-semantic: WMS
m=application 9 UDP/DTLS/SCTP webrtc-datachannel
c=IN IP4 0.0.0.0
a=ice-ufrag:${_randomIceChars(4)}
a=ice-pwd:${_randomIceChars(22)}
a=ice-options:trickle
a=fingerprint:sha-256 ${_randomFingerprint()}
a=setup:${type == 'offer' ? 'actpass' : 'active'}
a=mid:data
a=sctp-port:5000
a=max-message-size:262144
''';

    return SessionDescription(type: type, sdp: sdp);
  }

  DataChannelWrapper _createChannel(String remotePeerId) =>
      DataChannelWrapper(
        label: _config.defaultChannel.label,
        remotePeerId: remotePeerId,
        config: _config.defaultChannel,
      );

  Future<void> _sendSignal(
    String targetPeerId,
    Map<String, dynamic> signal,
  ) async {
    final fn = onSignalReady;
    if (fn != null) await fn(targetPeerId, signal);
  }

  String _randomIceChars(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789+/';
    final rng = Random.secure();
    return List.generate(length, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  String _randomFingerprint() {
    final rng = Random.secure();
    return List.generate(
      32,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0').toUpperCase(),
    ).join(':');
  }

  void _assertInitialized() {
    if (!_initialized) {
      throw const InitializationException(
        'WebRTCManager has not been initialized. Call initialize() first.',
      );
    }
  }

  void _startCleanupTimer() {
    Timer.periodic(const Duration(minutes: 1), (_) {
      _pendingOffers.removeWhere((_, p) => p.isExpired);
    });
  }
}
