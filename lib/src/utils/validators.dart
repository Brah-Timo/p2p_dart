/// Input validation helpers.
library;

import '../dht/kademlia.dart';

// ─── Validators ───────────────────────────────────────────────────────────────

/// Collection of validation predicates and assertion helpers.
abstract final class Validators {
  Validators._();

  // ─── Peer ID ──────────────────────────────────────────────────────────────

  /// Returns `true` if [peerId] is a valid 40-hex-character Kademlia ID.
  static bool isPeerId(String peerId) => Kademlia.isValidId(peerId);

  /// Throws [ArgumentError] if [peerId] is not a valid peer ID.
  static void requirePeerId(String peerId, [String paramName = 'peerId']) {
    if (!isPeerId(peerId)) {
      throw ArgumentError.value(
        peerId,
        paramName,
        'Must be a 40-character hex Kademlia peer ID',
      );
    }
  }

  // ─── Port ─────────────────────────────────────────────────────────────────

  /// Returns `true` if [port] is a valid TCP/UDP port number (1–65535).
  static bool isValidPort(int port) => port >= 1 && port <= 65535;

  /// Throws [ArgumentError] if [port] is not a valid port number.
  static void requirePort(int port, [String paramName = 'port']) {
    if (!isValidPort(port)) {
      throw ArgumentError.value(
        port,
        paramName,
        'Port must be in range 1–65535',
      );
    }
  }

  // ─── Hostname ────────────────────────────────────────────────────────────

  /// Returns `true` if [host] looks like a valid IPv4 address.
  static bool isIPv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  /// Returns `true` if [host] looks like a valid hostname or IP.
  static bool isHostname(String host) {
    if (host.isEmpty) return false;
    if (isIPv4(host)) return true;
    // Simple hostname check: alphanumeric + hyphens/dots.
    return RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9\-\.]*[a-zA-Z0-9])?$')
        .hasMatch(host);
  }

  // ─── Data Payload ────────────────────────────────────────────────────────

  /// Throws [ArgumentError] if [data] exceeds [maxBytes] after JSON encoding.
  static void requirePayloadSize(
    Map<String, dynamic> data,
    int maxBytes, {
    String paramName = 'data',
  }) {
    // Rough estimate: JSON overhead ~2 bytes/key.
    final approxSize = data.toString().length;
    if (approxSize > maxBytes) {
      throw ArgumentError.value(
        approxSize,
        paramName,
        'Payload too large (~$approxSize bytes, max $maxBytes)',
      );
    }
  }

  // ─── Non-empty ────────────────────────────────────────────────────────────

  /// Throws [ArgumentError] if [value] is null or empty.
  static void requireNonEmpty(String? value, [String paramName = 'value']) {
    if (value == null || value.isEmpty) {
      throw ArgumentError('$paramName must not be null or empty');
    }
  }
}
