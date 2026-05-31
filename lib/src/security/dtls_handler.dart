/// DTLS fingerprint and handshake helpers.
///
/// In a full WebRTC stack, DTLS is handled natively by the WebRTC engine.
/// This file provides the Dart-side utilities for generating and verifying
/// DTLS fingerprints that appear in SDP bodies.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'crypto_utils.dart';

// ─── DTLS Fingerprint ────────────────────────────────────────────────────────

/// A DTLS certificate fingerprint as exchanged in SDP.
class DtlsFingerprint {
  /// Hash algorithm identifier (e.g. `'sha-256'`).
  final String algorithm;

  /// Colon-separated hex fingerprint string.
  final String value;

  /// Creates a [DtlsFingerprint].
  const DtlsFingerprint({required this.algorithm, required this.value});

  /// Returns the SDP `a=fingerprint:` line.
  String toSdpLine() => 'a=fingerprint:$algorithm $value';

  /// Parses from an SDP fingerprint line.
  factory DtlsFingerprint.fromSdpLine(String line) {
    final clean = line.replaceFirst('a=fingerprint:', '').trim();
    final spaceIdx = clean.indexOf(' ');
    return DtlsFingerprint(
      algorithm: clean.substring(0, spaceIdx),
      value: clean.substring(spaceIdx + 1),
    );
  }

  /// Returns the raw bytes of the fingerprint (strips colons).
  Uint8List get bytes =>
      CryptoUtils.hexToBytes(value.replaceAll(':', ''));

  @override
  String toString() => 'DtlsFingerprint($algorithm: ${value.substring(0, 23)}…)';

  @override
  bool operator ==(Object other) =>
      other is DtlsFingerprint &&
      other.algorithm == algorithm &&
      other.value.toLowerCase() == value.toLowerCase();

  @override
  int get hashCode => Object.hash(algorithm, value.toLowerCase());
}

// ─── DTLS Handler ────────────────────────────────────────────────────────────

/// Manages the DTLS certificate and fingerprint for a single node.
///
/// In a real implementation this would generate an actual X.509 certificate
/// and interact with the native WebRTC DTLS stack.  This class simulates the
/// fingerprint exchange portion.
class DtlsHandler {
  /// The pre-generated self-signed certificate bytes (DER format).
  late final Uint8List _certificate;

  /// The computed SHA-256 fingerprint.
  late final DtlsFingerprint fingerprint;

  bool _initialized = false;

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  /// Generates a self-signed certificate and computes its fingerprint.
  ///
  /// In production this uses the native WebRTC engine's certificate API.
  /// Here we generate a deterministic certificate from a random key pair.
  void initialize() {
    if (_initialized) return;

    // Simulate a DER-encoded certificate body.
    final certBody = CryptoUtils.randomBytes(512);
    _certificate = _buildFakeDerCert(certBody);

    // SHA-256 fingerprint.
    final digest = sha256.convert(_certificate);
    final colonHex = digest.bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(':');

    fingerprint = DtlsFingerprint(algorithm: 'sha-256', value: colonHex);
    _initialized = true;
  }

  // ─── Fingerprint Verification ─────────────────────────────────────────────

  /// Verifies that [remote] matches our expected fingerprint.
  ///
  /// Returns `true` if the fingerprints match (constant-time comparison).
  bool verifyRemoteFingerprint(DtlsFingerprint remote) {
    if (!_initialized) return false;
    if (remote.algorithm.toLowerCase() != fingerprint.algorithm.toLowerCase()) {
      return false;
    }
    return CryptoUtils.constantTimeEqual(
      remote.bytes,
      fingerprint.bytes,
    );
  }

  /// Returns the SDP fingerprint attribute for this node.
  String get sdpFingerprintLine => fingerprint.toSdpLine();

  // ─── Private Helpers ────────────────────────────────────────────────────

  Uint8List _buildFakeDerCert(Uint8List body) {
    // DER SEQUENCE header (simplified).
    final header = Uint8List.fromList([0x30, 0x82, (body.length >> 8) & 0xFF, body.length & 0xFF]);
    final cert = Uint8List(header.length + body.length);
    cert.setAll(0, header);
    cert.setAll(header.length, body);
    return cert;
  }
}

// ─── DTLS Role ────────────────────────────────────────────────────────────────

/// The DTLS role of a peer in a connection.
enum DtlsRole {
  /// Active: initiates the DTLS handshake.
  client,

  /// Passive: accepts the DTLS handshake.
  server,

  /// Either role: accepts both.
  actpass,
}

// ─── DTLS Session ────────────────────────────────────────────────────────────

/// Records the outcome of a completed DTLS handshake.
class DtlsSession {
  /// The negotiated cipher suite.
  final String cipherSuite;

  /// The remote peer's verified fingerprint.
  final DtlsFingerprint remoteFingerprint;

  /// The SRTP master key derived from the DTLS handshake.
  final Uint8List srtpMasterKey;

  /// The SRTP master salt.
  final Uint8List srtpMasterSalt;

  /// Whether the session is valid.
  bool get isValid => srtpMasterKey.length == 16 && srtpMasterSalt.length == 14;

  /// Creates a [DtlsSession].
  const DtlsSession({
    required this.cipherSuite,
    required this.remoteFingerprint,
    required this.srtpMasterKey,
    required this.srtpMasterSalt,
  });

  @override
  String toString() =>
      'DtlsSession(cipher: $cipherSuite, valid: $isValid)';
}
