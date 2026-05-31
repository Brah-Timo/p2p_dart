/// Unit tests for the cryptographic utilities.
library;

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:p2p_dart/p2p_dart.dart';

void main() {
  group('CryptoUtils', () {
    test('randomBytes generates the requested length', () {
      final bytes = CryptoUtils.randomBytes(32);
      expect(bytes.length, equals(32));
    });

    test('randomBytes is non-deterministic', () {
      final a = CryptoUtils.randomBytes(16);
      final b = CryptoUtils.randomBytes(16);
      expect(a, isNot(equals(b)));
    });

    test('sha256Hash is deterministic', () {
      final data = Uint8List.fromList([1, 2, 3]);
      expect(CryptoUtils.sha256Hash(data), equals(CryptoUtils.sha256Hash(data)));
    });

    test('bytesToHex and hexToBytes are inverse', () {
      final original = CryptoUtils.randomBytes(20);
      final hex = CryptoUtils.bytesToHex(original);
      final back = CryptoUtils.hexToBytes(hex);
      expect(back, equals(original));
    });

    test('hmacSha256 changes with different keys', () {
      final data = Uint8List.fromList('test'.codeUnits);
      final key1 = CryptoUtils.randomBytes(32);
      final key2 = CryptoUtils.randomBytes(32);
      expect(
        CryptoUtils.hmacSha256(key1, data),
        isNot(equals(CryptoUtils.hmacSha256(key2, data))),
      );
    });

    test('constantTimeEqual is true for equal arrays', () {
      final a = Uint8List.fromList([1, 2, 3, 4]);
      final b = Uint8List.fromList([1, 2, 3, 4]);
      expect(CryptoUtils.constantTimeEqual(a, b), isTrue);
    });

    test('constantTimeEqual is false for different arrays', () {
      final a = Uint8List.fromList([1, 2, 3, 4]);
      final b = Uint8List.fromList([1, 2, 3, 5]);
      expect(CryptoUtils.constantTimeEqual(a, b), isFalse);
    });

    test('constantTimeEqual is false for different lengths', () {
      final a = Uint8List.fromList([1, 2, 3]);
      final b = Uint8List.fromList([1, 2, 3, 4]);
      expect(CryptoUtils.constantTimeEqual(a, b), isFalse);
    });
  });

  group('AES-GCM Encryption', () {
    test('encrypt and decrypt round-trip', () {
      final key = CryptoUtils.randomBytes(32);
      final plaintext = Uint8List.fromList('Hello, World!'.codeUnits);

      final encrypted = CryptoUtils.aesGcmEncrypt(key, plaintext);
      final decrypted = CryptoUtils.aesGcmDecrypt(key, encrypted);

      expect(decrypted, equals(plaintext));
    });

    test('different IVs produce different ciphertexts', () {
      final key = CryptoUtils.randomBytes(32);
      final plaintext = Uint8List.fromList('test'.codeUnits);

      final e1 = CryptoUtils.aesGcmEncrypt(key, plaintext);
      final e2 = CryptoUtils.aesGcmEncrypt(key, plaintext);

      // IVs should differ (random).
      expect(e1.iv, isNot(equals(e2.iv)));
    });

    test('wrong key fails decryption', () {
      final key1 = CryptoUtils.randomBytes(32);
      final key2 = CryptoUtils.randomBytes(32);
      final plaintext = Uint8List.fromList('secret'.codeUnits);

      final encrypted = CryptoUtils.aesGcmEncrypt(key1, plaintext);

      expect(
        () => CryptoUtils.aesGcmDecrypt(key2, encrypted),
        throwsA(anything),
      );
    });
  });

  group('EncryptedPayload', () {
    test('encode and decode round-trip', () {
      final iv = CryptoUtils.randomBytes(12);
      final ct = CryptoUtils.randomBytes(64);
      final payload = EncryptedPayload(iv: iv, ciphertext: ct);

      final encoded = payload.encode();
      final decoded = EncryptedPayload.decode(encoded);

      expect(decoded.iv, equals(iv));
      expect(decoded.ciphertext, equals(ct));
    });
  });

  group('Key Exchange', () {
    test('two parties derive the same shared secret', () {
      final aliceKeyPair = DHKeyExchange.generateKeyPair();
      final bobKeyPair = DHKeyExchange.generateKeyPair();

      final aliceSecret = DHKeyExchange.computeSharedSecret(
        aliceKeyPair.privateKeyBytes,
        bobKeyPair.publicKeyBytes,
      );

      final bobSecret = DHKeyExchange.computeSharedSecret(
        bobKeyPair.privateKeyBytes,
        aliceKeyPair.publicKeyBytes,
      );

      expect(aliceSecret, equals(bobSecret));
    });

    test('session keys are 32 bytes each', () {
      final alice = DHKeyExchange.generateKeyPair();
      final bob = DHKeyExchange.generateKeyPair();

      final secret = DHKeyExchange.computeSharedSecret(
        alice.privateKeyBytes,
        bob.publicKeyBytes,
      );

      final keys = DHKeyExchange.deriveSessionKeys(
        secret,
        localPeerId: 'a' * 40,
        remotePeerId: 'b' * 40,
      );

      expect(keys.encryptKey.length, equals(32));
      expect(keys.decryptKey.length, equals(32));
    });
  });
}
