/// String utility extensions.
library;

import 'dart:convert';
import 'dart:typed_data';

/// Convenience extensions on [String].
extension P2PStringExtensions on String {
  /// Encodes this string as UTF-8 bytes.
  Uint8List toUtf8Bytes() => Uint8List.fromList(utf8.encode(this));

  /// Decodes this string as Base64.
  Uint8List fromBase64() => base64Decode(this);

  /// Returns `true` if this string looks like a valid peer ID.
  bool get isValidPeerId =>
      length == 40 &&
      RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(this);

  /// Truncates this string to [maxLength] characters, appending [ellipsis].
  String truncate(int maxLength, {String ellipsis = '…'}) {
    if (length <= maxLength) return this;
    return '${substring(0, maxLength)}$ellipsis';
  }

  /// Returns an abbreviated peer ID `"abcdef01…"` form.
  String get shortPeerId => truncate(8);

  /// Converts camelCase to snake_case.
  String get toSnakeCase {
    return replaceAllMapped(
      RegExp(r'[A-Z]'),
      (m) => '_${m.group(0)!.toLowerCase()}',
    ).replaceFirst(RegExp(r'^_'), '');
  }

  /// Returns `true` if this string is a valid IPv4 address.
  bool get isIPv4 {
    final parts = split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  /// Parses this string as a JSON map (or returns `null` on failure).
  Map<String, dynamic>? tryParseJson() {
    try {
      return json.decode(this) as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }
}

/// Convenience extensions on [Uint8List].
extension Uint8ListExtensions on Uint8List {
  /// Decodes these bytes as a UTF-8 string.
  String toUtf8String() => utf8.decode(this);

  /// Encodes these bytes as Base64.
  String toBase64() => base64Encode(this);

  /// Encodes these bytes as lowercase hex.
  String toHex() =>
      map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Returns the first [n] bytes.
  Uint8List take(int n) => Uint8List.sublistView(this, 0, n.clamp(0, length));
}
