/// Peer authentication via challenge-response.
library;

import 'dart:typed_data';

import '../core/exceptions.dart';
import '../utils/logger.dart';
import 'crypto_utils.dart';

// ─── Auth Challenge ───────────────────────────────────────────────────────────

/// A nonce-based authentication challenge sent to a remote peer.
class AuthChallenge {
  /// The 32-byte random nonce.
  final Uint8List nonce;

  /// When the challenge was issued (for timeout detection).
  final DateTime issuedAt;

  /// Creates an [AuthChallenge].
  AuthChallenge({Uint8List? nonce})
      : nonce = nonce ?? CryptoUtils.randomBytes(32),
        issuedAt = DateTime.now();

  /// Returns `true` if this challenge has expired (older than 30 seconds).
  bool get isExpired =>
      DateTime.now().difference(issuedAt) > const Duration(seconds: 30);

  /// Returns the nonce as a hex string.
  String get nonceHex => CryptoUtils.bytesToHex(nonce);
}

// ─── Auth Response ────────────────────────────────────────────────────────────

/// The signed response a peer sends back to an [AuthChallenge].
class AuthResponse {
  /// The nonce from the challenge.
  final Uint8List nonce;

  /// HMAC-SHA256(sharedKey, nonce).
  final Uint8List signature;

  /// The responder's peer ID.
  final String responderId;

  /// Creates an [AuthResponse].
  const AuthResponse({
    required this.nonce,
    required this.signature,
    required this.responderId,
  });

  /// Serialises to a JSON map.
  Map<String, dynamic> toJson() => {
        'nonce': CryptoUtils.bytesToHex(nonce),
        'signature': CryptoUtils.bytesToHex(signature),
        'responderId': responderId,
      };

  /// Deserialises from a JSON map.
  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        nonce: CryptoUtils.hexToBytes(json['nonce'] as String),
        signature: CryptoUtils.hexToBytes(json['signature'] as String),
        responderId: json['responderId'] as String,
      );
}

// ─── Auth Manager ────────────────────────────────────────────────────────────

/// Manages peer authentication.
///
/// Uses a symmetric HMAC-based challenge-response protocol.  Both peers must
/// share a [presharedKey] (or derive one from their ECDH session key).
///
/// Workflow:
/// 1. [issueChallenge] → send the nonce to the remote peer.
/// 2. Remote peer calls [signChallenge] with the nonce → sends [AuthResponse].
/// 3. [verifyResponse] → validates the HMAC.
class AuthManager {
  final String _localPeerId;
  final Uint8List _presharedKey;
  final P2PLogger _log;

  // Active challenges keyed by remote peer ID.
  final Map<String, AuthChallenge> _challenges = {};

  // Verified peer IDs.
  final Set<String> _verifiedPeers = {};

  // Failure counts.
  final Map<String, int> _failureCounts = {};

  /// Maximum allowed auth failures before a peer is rejected.
  final int maxFailures;

  // ─── Constructor ───────────────────────────────────────────────────────────

  /// Creates an [AuthManager].
  AuthManager({
    required String localPeerId,
    required Uint8List presharedKey,
    this.maxFailures = 5,
    P2PLogger? logger,
  })  : _localPeerId = localPeerId,
        _presharedKey = presharedKey,
        _log = logger ?? P2PLogger('AuthManager');

  // ─── Challenge Phase ──────────────────────────────────────────────────────

  /// Creates and stores a challenge for [remotePeerId].
  ///
  /// Returns the [AuthChallenge] whose nonce should be sent to the peer.
  AuthChallenge issueChallenge(String remotePeerId) {
    _cleanExpiredChallenges();
    final challenge = AuthChallenge();
    _challenges[remotePeerId] = challenge;
    _log.debug('Issued auth challenge to $remotePeerId');
    return challenge;
  }

  // ─── Response Phase ───────────────────────────────────────────────────────

  /// Signs a nonce (received as part of a challenge) with our [_presharedKey].
  ///
  /// Returns the [AuthResponse] to send back.
  AuthResponse signChallenge(Uint8List nonce) {
    final signature = CryptoUtils.hmacSha256(_presharedKey, nonce);
    return AuthResponse(
      nonce: nonce,
      signature: signature,
      responderId: _localPeerId,
    );
  }

  // ─── Verification Phase ───────────────────────────────────────────────────

  /// Verifies [response] against the stored challenge for the responder.
  ///
  /// Throws [AuthenticationException] if verification fails.
  bool verifyResponse(AuthResponse response) {
    final remotePeerId = response.responderId;
    final challenge = _challenges[remotePeerId];

    if (challenge == null) {
      throw AuthenticationException(
        remotePeerId,
        'No pending challenge found.',
      );
    }

    if (challenge.isExpired) {
      _challenges.remove(remotePeerId);
      throw AuthenticationException(remotePeerId, 'Challenge expired.');
    }

    if (!CryptoUtils.constantTimeEqual(challenge.nonce, response.nonce)) {
      _recordFailure(remotePeerId);
      throw AuthenticationException(remotePeerId, 'Nonce mismatch.');
    }

    final expectedSig = CryptoUtils.hmacSha256(_presharedKey, response.nonce);
    if (!CryptoUtils.constantTimeEqual(expectedSig, response.signature)) {
      _recordFailure(remotePeerId);
      throw AuthenticationException(remotePeerId, 'Invalid signature.');
    }

    _challenges.remove(remotePeerId);
    _verifiedPeers.add(remotePeerId);
    _failureCounts.remove(remotePeerId);
    _log.info('Peer $remotePeerId authenticated successfully.');
    return true;
  }

  // ─── Status Queries ───────────────────────────────────────────────────────

  /// Returns `true` if [remotePeerId] has been authenticated.
  bool isVerified(String remotePeerId) =>
      _verifiedPeers.contains(remotePeerId);

  /// Returns `true` if [remotePeerId] has exceeded the failure limit.
  bool isBanned(String remotePeerId) =>
      (_failureCounts[remotePeerId] ?? 0) >= maxFailures;

  /// Removes a peer from the verified set (e.g., on disconnect).
  void revoke(String remotePeerId) {
    _verifiedPeers.remove(remotePeerId);
    _challenges.remove(remotePeerId);
  }

  // ─── Private ────────────────────────────────────────────────────────────

  void _recordFailure(String peerId) {
    final count = (_failureCounts[peerId] ?? 0) + 1;
    _failureCounts[peerId] = count;
    _log.warning('Auth failure #$count for $peerId');

    if (count >= maxFailures) {
      _log.warning('Peer $peerId exceeded max auth failures — banning.');
    }
  }

  void _cleanExpiredChallenges() {
    _challenges.removeWhere((_, c) => c.isExpired);
  }
}
