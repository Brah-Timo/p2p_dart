/// Message-level encryption / decryption.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/exceptions.dart';
import 'crypto_utils.dart';
import 'key_exchange.dart';

// ─── Encrypted Message ────────────────────────────────────────────────────────

/// A fully encrypted P2P message envelope.
class EncryptedMessage {
  /// Sender's ephemeral public key (used for the shared secret).
  final Uint8List senderPublicKey;

  /// The AES-GCM encrypted payload.
  final EncryptedPayload payload;

  /// HMAC-SHA256 authentication tag over (senderPublicKey + iv + ciphertext).
  final Uint8List hmac;

  /// Creates an [EncryptedMessage].
  const EncryptedMessage({
    required this.senderPublicKey,
    required this.payload,
    required this.hmac,
  });

  /// Serialises to a JSON-safe map.
  Map<String, dynamic> toJson() => {
        'senderPubKey': CryptoUtils.toBase64(senderPublicKey),
        'payload': CryptoUtils.toBase64(payload.encode()),
        'hmac': CryptoUtils.toBase64(hmac),
      };

  /// Deserialises from a JSON map.
  factory EncryptedMessage.fromJson(Map<String, dynamic> json) {
    Uint8List b64Decode(String s) => base64Decode(s);
    return EncryptedMessage(
      senderPublicKey: b64Decode(json['senderPubKey'] as String),
      payload: EncryptedPayload.decode(b64Decode(json['payload'] as String)),
      hmac: b64Decode(json['hmac'] as String),
    );
  }
}

// ─── Message Encryptor ────────────────────────────────────────────────────────

/// Encrypts and decrypts application messages.
///
/// Each instance holds the local ephemeral key pair and the derived session
/// keys once [establishSession] has been called.
class MessageEncryptor {
  final KeyPair _localKeyPair;
  SessionKeys? _sessionKeys;

  /// Whether a session has been established.
  bool get hasSession => _sessionKeys != null;

  /// Returns the local public key to send to the remote peer.
  Uint8List get localPublicKey => _localKeyPair.publicKeyBytes;

  // ─── Constructor ───────────────────────────────────────────────────────────

  /// Creates a [MessageEncryptor] with a fresh ephemeral key pair.
  MessageEncryptor() : _localKeyPair = DHKeyExchange.generateKeyPair();

  /// Creates a [MessageEncryptor] from an existing [keyPair] (testing only).
  MessageEncryptor.fromKeyPair(this._localKeyPair);

  // ─── Session Establishment ────────────────────────────────────────────────

  /// Derives session keys from [remotePublicKeyBytes].
  ///
  /// Must be called before [encrypt] / [decrypt].
  void establishSession({
    required Uint8List remotePublicKeyBytes,
    required String localPeerId,
    required String remotePeerId,
  }) {
    final sharedSecret = DHKeyExchange.computeSharedSecret(
      _localKeyPair.privateKeyBytes,
      remotePublicKeyBytes,
    );

    _sessionKeys = DHKeyExchange.deriveSessionKeys(
      sharedSecret,
      localPeerId: localPeerId,
      remotePeerId: remotePeerId,
    );
  }

  // ─── Encryption ───────────────────────────────────────────────────────────

  /// Encrypts [plaintext] and returns an [EncryptedMessage].
  ///
  /// Throws [CryptoException] if the session has not been established.
  EncryptedMessage encrypt(Uint8List plaintext) {
    final keys = _requireSession();

    final payload = CryptoUtils.aesGcmEncrypt(keys.encryptKey, plaintext);

    // Compute HMAC over: publicKey | iv | ciphertext
    final macData = Uint8List(
      _localKeyPair.publicKeyBytes.length +
          payload.iv.length +
          payload.ciphertext.length,
    );
    macData.setAll(0, _localKeyPair.publicKeyBytes);
    macData.setAll(_localKeyPair.publicKeyBytes.length, payload.iv);
    macData.setAll(
      _localKeyPair.publicKeyBytes.length + payload.iv.length,
      payload.ciphertext,
    );

    final hmac = CryptoUtils.hmacSha256(keys.encryptKey, macData);

    return EncryptedMessage(
      senderPublicKey: _localKeyPair.publicKeyBytes,
      payload: payload,
      hmac: hmac,
    );
  }

  /// Encrypts a JSON [map].
  EncryptedMessage encryptJson(Map<String, dynamic> map) =>
      encrypt(Uint8List.fromList(utf8.encode(jsonEncode(map))));

  // ─── Decryption ───────────────────────────────────────────────────────────

  /// Decrypts an [EncryptedMessage] and returns the plaintext bytes.
  ///
  /// Throws [CryptoException] if the HMAC is invalid or decryption fails.
  Uint8List decrypt(EncryptedMessage message) {
    final keys = _requireSession();

    // Verify HMAC.
    final macData = Uint8List(
      message.senderPublicKey.length +
          message.payload.iv.length +
          message.payload.ciphertext.length,
    );
    macData.setAll(0, message.senderPublicKey);
    macData.setAll(message.senderPublicKey.length, message.payload.iv);
    macData.setAll(
      message.senderPublicKey.length + message.payload.iv.length,
      message.payload.ciphertext,
    );

    final expectedHmac = CryptoUtils.hmacSha256(keys.decryptKey, macData);

    if (!CryptoUtils.constantTimeEqual(expectedHmac, message.hmac)) {
      throw const CryptoException(
        'Message authentication failed: HMAC mismatch',
      );
    }

    try {
      return CryptoUtils.aesGcmDecrypt(keys.decryptKey, message.payload);
    } catch (e) {
      throw CryptoException('Decryption failed: $e', cause: e);
    }
  }

  /// Decrypts an [EncryptedMessage] and returns the JSON payload.
  Map<String, dynamic> decryptJson(EncryptedMessage message) {
    final bytes = decrypt(message);
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  // ─── Private ────────────────────────────────────────────────────────────

  SessionKeys _requireSession() {
    final keys = _sessionKeys;
    if (keys == null) {
      throw const CryptoException(
        'No session established. Call establishSession() first.',
      );
    }
    return keys;
  }
}
