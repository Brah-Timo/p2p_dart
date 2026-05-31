/// Diffie-Hellman key exchange (X25519 / ECDH over P-256).
library;

import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'crypto_utils.dart';

// ─── Key Pair ────────────────────────────────────────────────────────────────

/// An asymmetric key pair used for ECDH key exchange.
class KeyPair {
  /// Raw bytes of the private key.
  final Uint8List privateKeyBytes;

  /// Raw bytes of the public key (uncompressed SEC format for P-256).
  final Uint8List publicKeyBytes;

  /// Creates a [KeyPair].
  const KeyPair({
    required this.privateKeyBytes,
    required this.publicKeyBytes,
  });

  /// Abbreviated public key for logging.
  String get shortPublicKey =>
      CryptoUtils.bytesToHex(publicKeyBytes).substring(0, 16);

  @override
  String toString() => 'KeyPair(pub: $shortPublicKey…)';
}

// ─── DH Key Exchange ─────────────────────────────────────────────────────────

/// ECDH key exchange over NIST P-256.
///
/// Workflow:
/// 1. Both peers generate ephemeral key pairs via [generateKeyPair].
/// 2. Each peer sends its [KeyPair.publicKeyBytes] to the other.
/// 3. Each peer calls [computeSharedSecret] with its private key and the
///    remote's public key to derive the same 32-byte secret.
/// 4. The shared secret is then used to derive AES session keys via
///    [deriveSessionKeys].
abstract final class DHKeyExchange {
  DHKeyExchange._();

  // ─── Key Generation ────────────────────────────────────────────────────────

  /// Generates an ephemeral ECDH key pair over P-256.
  static KeyPair generateKeyPair() {
    final generator = ECKeyGenerator()
      ..init(
        ParametersWithRandom(
          ECKeyGeneratorParameters(ECDomainParameters('prime256v1')),
          _secureRandom(),
        ),
      );

    final pair = generator.generateKeyPair();
    final private = pair.privateKey as ECPrivateKey;
    final public = pair.publicKey as ECPublicKey;

    final privateBytes = _bigIntToBytes(private.d!, 32);
    final publicBytes = _encodePublicKey(public);

    return KeyPair(privateKeyBytes: privateBytes, publicKeyBytes: publicBytes);
  }

  // ─── Shared Secret Computation ─────────────────────────────────────────────

  /// Computes the ECDH shared secret from [localPrivateKeyBytes] and
  /// [remotePublicKeyBytes].
  ///
  /// Returns 32 raw bytes (the x-coordinate of the shared EC point).
  static Uint8List computeSharedSecret(
    Uint8List localPrivateKeyBytes,
    Uint8List remotePublicKeyBytes,
  ) {
    final domain = ECDomainParameters('prime256v1');

    final privateKey = ECPrivateKey(
      _bytesToBigInt(localPrivateKeyBytes),
      domain,
    );

    final publicKey = _decodePublicKey(remotePublicKeyBytes, domain);

    final agreement = ECDHBasicAgreement()..init(privateKey);
    final sharedPoint = agreement.calculateAgreement(publicKey);

    return _bigIntToBytes(sharedPoint, 32);
  }

  // ─── Session Key Derivation ───────────────────────────────────────────────

  /// Derives two symmetric AES-256 session keys (one per direction) from a
  /// raw [sharedSecret] using HKDF-SHA256.
  ///
  /// Returns a [SessionKeys] bundle.
  static SessionKeys deriveSessionKeys(
    Uint8List sharedSecret, {
    required String localPeerId,
    required String remotePeerId,
  }) {
    // Deterministic ordering so both sides derive the same keys.
    final ordered = localPeerId.compareTo(remotePeerId) < 0
        ? localPeerId + remotePeerId
        : remotePeerId + localPeerId;

    final salt = CryptoUtils.sha256Hash(
      Uint8List.fromList(ordered.codeUnits),
    );

    final prk = CryptoUtils.hmacSha256(salt, sharedSecret);

    // Expand: two 32-byte keys via T(1) and T(2).
    final t1 = CryptoUtils.hmacSha256(prk, Uint8List.fromList([...ordered.codeUnits, 0x01]));
    final t2 = CryptoUtils.hmacSha256(prk, Uint8List.fromList([...t1, 0x02]));

    return SessionKeys(encryptKey: t1, decryptKey: t2);
  }

  // ─── Private Helpers ────────────────────────────────────────────────────

  static SecureRandom _secureRandom() {
    final rng = FortunaRandom()
      ..seed(KeyParameter(CryptoUtils.randomBytes(32)));
    return rng;
  }

  static Uint8List _bigIntToBytes(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    final result = Uint8List(length);
    for (var i = 0; i < length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static Uint8List _encodePublicKey(ECPublicKey key) {
    final q = key.Q!;
    final x = _bigIntToBytes(q.x!.toBigInteger()!, 32);
    final y = _bigIntToBytes(q.y!.toBigInteger()!, 32);
    final encoded = Uint8List(65);
    encoded[0] = 0x04; // uncompressed
    encoded.setAll(1, x);
    encoded.setAll(33, y);
    return encoded;
  }

  static ECPublicKey _decodePublicKey(Uint8List bytes, ECDomainParameters domain) {
    final point = domain.curve.decodePoint(bytes)!;
    return ECPublicKey(point, domain);
  }
}

// ─── Session Keys ────────────────────────────────────────────────────────────

/// A pair of symmetric AES-256 keys derived from a ECDH shared secret.
class SessionKeys {
  /// Key used to encrypt outgoing messages.
  final Uint8List encryptKey;

  /// Key used to decrypt incoming messages.
  final Uint8List decryptKey;

  /// Creates [SessionKeys].
  const SessionKeys({
    required this.encryptKey,
    required this.decryptKey,
  });

  @override
  String toString() =>
      'SessionKeys(encKey: ${CryptoUtils.bytesToHex(encryptKey).substring(0, 8)}…)';
}
