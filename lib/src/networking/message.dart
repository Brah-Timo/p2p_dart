/// Protocol message definitions.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/enums.dart';

// ─── Message ─────────────────────────────────────────────────────────────────

/// A protocol message exchanged between two peers.
///
/// All messages carry:
/// - A [type] that classifies the message.
/// - A [correlationId] for request/response matching.
/// - An [senderId] that identifies the originator.
/// - An optional [payload].
class P2PMessage {
  /// Message type.
  final MessageType type;

  /// Correlation ID — used to match responses to requests.
  final String correlationId;

  /// Peer ID of the sender.
  final String senderId;

  /// When the message was created (Unix ms).
  final int timestamp;

  /// Application-level payload.
  final Map<String, dynamic>? payload;

  /// Raw binary payload (used for file chunks, etc.).
  final Uint8List? binaryPayload;

  /// Protocol version of the sender.
  final String protocolVersion;

  /// Creates a [P2PMessage].
  P2PMessage({
    required this.type,
    required this.senderId,
    String? correlationId,
    this.payload,
    this.binaryPayload,
    this.protocolVersion = '1.0.0',
    int? timestamp,
  })  : correlationId = correlationId ?? _generateId(),
        timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  // ─── Serialisation ────────────────────────────────────────────────────────

  /// Encodes the message to a JSON string.
  String encode() => jsonEncode(toJson());

  /// Encodes the message to JSON bytes.
  Uint8List encodeBytes() => Uint8List.fromList(utf8.encode(encode()));

  /// Returns a JSON-serialisable map.
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'correlationId': correlationId,
        'senderId': senderId,
        'timestamp': timestamp,
        'protocolVersion': protocolVersion,
        if (payload != null) 'payload': payload,
        if (binaryPayload != null)
          'binaryPayload': base64Encode(binaryPayload!),
      };

  /// Decodes from a JSON string.
  factory P2PMessage.decode(String raw) =>
      P2PMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Decodes from JSON bytes.
  factory P2PMessage.decodeBytes(Uint8List bytes) =>
      P2PMessage.decode(utf8.decode(bytes));

  /// Reconstructs from a JSON map.
  factory P2PMessage.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    final type = MessageType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => MessageType.data,
    );

    Uint8List? binary;
    final rawBinary = json['binaryPayload'];
    if (rawBinary != null) {
      binary = base64Decode(rawBinary as String);
    }

    return P2PMessage(
      type: type,
      correlationId: json['correlationId'] as String?,
      senderId: json['senderId'] as String,
      payload: json['payload'] as Map<String, dynamic>?,
      binaryPayload: binary,
      protocolVersion: (json['protocolVersion'] as String?) ?? '1.0.0',
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }

  // ─── Factory Constructors ────────────────────────────────────────────────

  /// Creates a DATA message wrapping [data].
  factory P2PMessage.data(String senderId, Map<String, dynamic> data) =>
      P2PMessage(type: MessageType.data, senderId: senderId, payload: data);

  /// Creates a PING message.
  factory P2PMessage.ping(String senderId) =>
      P2PMessage(type: MessageType.ping, senderId: senderId);

  /// Creates a PONG response to a [ping].
  factory P2PMessage.pong(String senderId, String replyTo) =>
      P2PMessage(
        type: MessageType.pong,
        senderId: senderId,
        correlationId: replyTo,
      );

  /// Creates an ACK message for [messageId].
  factory P2PMessage.ack(String senderId, String messageId) =>
      P2PMessage(
        type: MessageType.ack,
        senderId: senderId,
        correlationId: messageId,
      );

  /// Creates a GOODBYE message.
  factory P2PMessage.goodbye(String senderId) =>
      P2PMessage(type: MessageType.goodbye, senderId: senderId);

  /// Creates an ERROR message.
  factory P2PMessage.error(String senderId, String errorMessage) =>
      P2PMessage(
        type: MessageType.error,
        senderId: senderId,
        payload: {'error': errorMessage},
      );

  // ─── Helpers ─────────────────────────────────────────────────────────────

  /// Returns `true` if the message is a protocol-level control message.
  bool get isControl => type == MessageType.ping ||
      type == MessageType.pong ||
      type == MessageType.ack ||
      type == MessageType.goodbye ||
      type == MessageType.error;

  /// Returns the age of this message.
  Duration get age =>
      Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - timestamp);

  @override
  String toString() =>
      'P2PMessage(type: ${type.name}, '
      'from: ${senderId.substring(0, 8)}…, '
      'age: ${age.inMilliseconds}ms)';

  static String _generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = now ^ (now << 16);
    return rand.toRadixString(36);
  }
}
