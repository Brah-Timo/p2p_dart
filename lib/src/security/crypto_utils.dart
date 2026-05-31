/// Cryptographic utility functions.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

// ─── Crypto Utils ────────────────────────────────────────────────────────────

/// Collection of pure-function cryptographic helpers.
abstract final class CryptoUtils {
  CryptoUtils._();

  // ─── Random Bytes ──────────────────────────────────────────────────────────

  /// Generates [length] cryptographically secure random bytes.
  static Uint8List randomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => rng.nextInt(256)),
    );
  }

  /// Generates a random nonce of [length] bytes, encoded as a hex string.
  static String randomNonce({int length = 16}) =>
      bytesToHex(randomBytes(length));

  // ─── Hashing ──────────────────────────────────────────────────────────────

  /// Returns the SHA-256 hash of [data].
  static Uint8List sha256Hash(Uint8List data) =>
      Uint8List.fromList(sha256.convert(data).bytes);

  /// Returns the SHA-1 hash of [data].
  static Uint8List sha1Hash(Uint8List data) =>
      Uint8List.fromList(sha1.convert(data).bytes);

  /// Returns the HMAC-SHA256 of [data] authenticated with [key].
  static Uint8List hmacSha256(Uint8List key, Uint8List data) {
    final hmac = Hmac(sha256, key);
    return Uint8List.fromList(hmac.convert(data).bytes);
  }

  // ─── Encoding Helpers ─────────────────────────────────────────────────────

  /// Converts [bytes] to lowercase hex.
  static String bytesToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Parses a hex string to bytes.
  static Uint8List hexToBytes(String hex) {
    final clean = hex.toLowerCase();
    final result = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  /// Encodes [bytes] to Base64.
  static String toBase64(Uint8List bytes) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i += 3) {
      final b0 = bytes[i];
      final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;

      buffer.write(chars[b0 >> 2]);
      buffer.write(chars[((b0 & 3) << 4) | (b1 >> 4)]);
      buffer.write(i + 1 < bytes.length ? chars[((b1 & 0xF) << 2) | (b2 >> 6)] : '=');
      buffer.write(i + 2 < bytes.length ? chars[b2 & 0x3F] : '=');
    }
    return buffer.toString();
  }

  // ─── AES-GCM Encryption ───────────────────────────────────────────────────

  /// Encrypts [plaintext] with AES-256-GCM using [key] and a random IV.
  ///
  /// Returns a [EncryptedPayload] containing the IV and ciphertext.
  static EncryptedPayload aesGcmEncrypt(Uint8List key, Uint8List plaintext) {
    assert(key.length == 32, 'AES-256 requires a 32-byte key');

    final iv = randomBytes(12); // 96-bit IV for GCM
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128, // tag length in bits
          iv,
          Uint8List(0), // no AAD
        ),
      );

    final ciphertext = Uint8List(cipher.getOutputSize(plaintext.length));
    var offset = 0;
    offset += cipher.processBytes(plaintext, 0, plaintext.length, ciphertext, offset);
    offset += cipher.doFinal(ciphertext, offset);

    return EncryptedPayload(iv: iv, ciphertext: ciphertext.sublist(0, offset));
  }

  /// Decrypts [payload] with AES-256-GCM using [key].
  ///
  /// Throws [InvalidCipherTextException] if the authentication tag is invalid.
  static Uint8List aesGcmDecrypt(Uint8List key, EncryptedPayload payload) {
    assert(key.length == 32, 'AES-256 requires a 32-byte key');

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          payload.iv,
          Uint8List(0),
        ),
      );

    final plaintext = Uint8List(cipher.getOutputSize(payload.ciphertext.length));
    var offset = 0;
    offset += cipher.processBytes(
      payload.ciphertext, 0, payload.ciphertext.length, plaintext, offset,
    );
    offset += cipher.doFinal(plaintext, offset);
    return plaintext.sublist(0, offset);
  }

  // ─── Key Derivation ───────────────────────────────────────────────────────

  /// Derives a key from [password] and [salt] using PBKDF2-HMAC-SHA256.
  ///
  /// [iterations] defaults to 100 000 (NIST minimum for interactive logins).
  static Uint8List deriveKey(
    Uint8List password,
    Uint8List salt, {
    int keyLength = 32,
    int iterations = 100000,
  }) {
    final params = Pbkdf2Parameters(salt, iterations, keyLength);
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(params);

    final key = Uint8List(keyLength);
    pbkdf2.deriveKey(password, 0, key, 0);
    return key;
  }

  // ─── Constant-time Comparison ─────────────────────────────────────────────

  /// Compares two byte arrays in constant time to prevent timing attacks.
  static bool constantTimeEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}

// ─── Encrypted Payload ────────────────────────────────────────────────────────

/// Container for an AES-GCM encrypted message (IV + ciphertext).
class EncryptedPayload {
  /// Initialisation vector (12 bytes for GCM).
  final Uint8List iv;

  /// Ciphertext (includes GCM authentication tag appended by PointyCastle).
  final Uint8List ciphertext;

  /// Creates an [EncryptedPayload].
  const EncryptedPayload({required this.iv, required this.ciphertext});

  /// Serialises to a single byte array: [ivLength(1)][iv][ciphertext].
  Uint8List encode() {
    final result = Uint8List(1 + iv.length + ciphertext.length);
    result[0] = iv.length;
    result.setAll(1, iv);
    result.setAll(1 + iv.length, ciphertext);
    return result;
  }

  /// Deserialises from the encoded format.
  factory EncryptedPayload.decode(Uint8List bytes) {
    final ivLen = bytes[0];
    final iv = bytes.sublist(1, 1 + ivLen);
    final ciphertext = bytes.sublist(1 + ivLen);
    return EncryptedPayload(iv: iv, ciphertext: ciphertext);
  }

  @override
  String toString() =>
      'EncryptedPayload(ivLen: ${iv.length}, ciphertextLen: ${ciphertext.length})';
}
