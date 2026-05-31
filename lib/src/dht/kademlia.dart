/// Kademlia XOR-metric utilities and ID helpers.
library;

import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

// ─── ID Length Constant ───────────────────────────────────────────────────────

/// Number of bytes in a Kademlia node ID (160 bits = 20 bytes).
const int kIdBytes = 20;

/// Number of hex characters in a Kademlia node ID.
const int kIdHexLength = kIdBytes * 2;

// ─── Kademlia Utilities ───────────────────────────────────────────────────────

/// Pure-function Kademlia ID and XOR-metric helpers.
abstract final class Kademlia {
  Kademlia._();

  // ─── ID Generation ──────────────────────────────────────────────────────────

  /// Generates a random 160-bit Kademlia ID encoded as a 40-char hex string.
  static String generateId() {
    final rng = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(kIdBytes, (_) => rng.nextInt(256)),
    );
    return _bytesToHex(bytes);
  }

  /// Derives a deterministic peer ID from a public key (SHA-1 of the key).
  static String idFromPublicKey(Uint8List publicKeyBytes) {
    final digest = sha1.convert(publicKeyBytes);
    return _bytesToHex(Uint8List.fromList(digest.bytes));
  }

  /// Derives a deterministic content-addressable key from arbitrary bytes.
  static String contentKey(Uint8List data) {
    final digest = sha1.convert(data);
    return _bytesToHex(Uint8List.fromList(digest.bytes));
  }

  /// Derives a key from a UTF-8 string.
  static String keyFromString(String value) {
    final digest = sha1.convert(value.codeUnits);
    return _bytesToHex(Uint8List.fromList(digest.bytes));
  }

  // ─── XOR Metric ─────────────────────────────────────────────────────────────

  /// Computes the XOR distance between two 160-bit IDs.
  ///
  /// Returns a [BigInt] so that arbitrarily large distances can be compared.
  static BigInt distance(String idA, String idB) {
    final bytesA = _hexToBytes(idA);
    final bytesB = _hexToBytes(idB);

    final xored = Uint8List(kIdBytes);
    for (var i = 0; i < kIdBytes; i++) {
      xored[i] = bytesA[i] ^ bytesB[i];
    }

    return _bytesToBigInt(xored);
  }

  /// Returns the 0-based index of the highest differing bit between two IDs.
  ///
  /// This is the k-bucket index to which the remote peer maps.
  /// Returns 0 if the IDs are identical.
  static int bucketIndex(String localId, String remoteId) {
    final bytesA = _hexToBytes(localId);
    final bytesB = _hexToBytes(remoteId);

    for (var bytePos = 0; bytePos < kIdBytes; bytePos++) {
      final xorByte = bytesA[bytePos] ^ bytesB[bytePos];
      if (xorByte != 0) {
        // Find highest set bit in this byte.
        final bitPos = (kIdBytes - bytePos - 1) * 8 + _highBit(xorByte);
        return bitPos;
      }
    }
    return 0; // IDs are identical
  }

  /// Sorts [peers] by XOR distance from [targetId] ascending.
  static List<T> sortByDistance<T>({
    required String targetId,
    required List<T> peers,
    required String Function(T) getId,
  }) {
    final sorted = List<T>.from(peers)
      ..sort((a, b) {
        final da = distance(targetId, getId(a));
        final db = distance(targetId, getId(b));
        return da.compareTo(db);
      });
    return sorted;
  }

  /// Picks the [count] closest peers to [targetId] from [candidates].
  static List<T> closestN<T>({
    required String targetId,
    required List<T> candidates,
    required String Function(T) getId,
    required int count,
  }) {
    final sorted = sortByDistance(
      targetId: targetId,
      peers: candidates,
      getId: getId,
    );
    return sorted.take(count).toList();
  }

  // ─── Validation ─────────────────────────────────────────────────────────────

  /// Returns `true` if [id] is a valid 40-character hex Kademlia ID.
  static bool isValidId(String id) {
    if (id.length != kIdHexLength) return false;
    return RegExp(r'^[0-9a-f]{40}$', caseSensitive: false).hasMatch(id);
  }

  // ─── Private Helpers ────────────────────────────────────────────────────────

  static String _bytesToHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _hexToBytes(String hex) {
    final normalized = hex.toLowerCase().padLeft(kIdHexLength, '0');
    final bytes = Uint8List(kIdBytes);
    for (var i = 0; i < kIdBytes; i++) {
      bytes[i] = int.parse(normalized.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  /// Returns the position of the highest set bit in [byte] (0-indexed from LSB).
  static int _highBit(int byte) {
    int pos = 7;
    while (pos >= 0 && (byte & (1 << pos)) == 0) {
      pos--;
    }
    return pos;
  }
}

// ─── ID Generator ─────────────────────────────────────────────────────────────

/// Stateful helper that generates unique, non-repeating Kademlia IDs.
class KademliaIdGenerator {
  /// Generates a random 160-bit Kademlia peer ID.
  String next() => Kademlia.generateId();

  /// Generates a deterministic ID from a [seed] string (SHA-1 of UTF-8 bytes).
  String fromSeed(String seed) => Kademlia.keyFromString(seed);
}
