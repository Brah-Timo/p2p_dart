/// Low-level packet framing for the transport layer.
library;

import 'dart:typed_data';

// ─── Packet Header ────────────────────────────────────────────────────────────

/// Framed packet header (8 bytes):
///
/// ```
/// ┌──────────┬──────────┬──────────┬──────────┬──────────────────────────────┐
/// │ Version  │  Flags   │  Type    │ Reserved │         Payload Length        │
/// │  1 byte  │  1 byte  │  1 byte  │  1 byte  │           4 bytes             │
/// └──────────┴──────────┴──────────┴──────────┴──────────────────────────────┘
/// ```
class PacketHeader {
  /// Size of every packet header in bytes.
  static const int headerSize = 8;

  /// Current protocol version written into the [version] field.
  static const int currentVersion = 1;

  /// Protocol version.
  final int version;

  /// Bit-field flags.
  final int flags;

  /// Packet type byte.
  final int type;

  /// Length of the following payload in bytes.
  final int payloadLength;

  /// Flag: message is compressed.
  bool get isCompressed => (flags & 0x01) != 0;

  /// Flag: message is encrypted.
  bool get isEncrypted => (flags & 0x02) != 0;

  /// Flag: message requires acknowledgement.
  bool get requiresAck => (flags & 0x04) != 0;

  /// Flag: this is a fragmented packet.
  bool get isFragment => (flags & 0x08) != 0;

  /// Flag: this is the last fragment.
  bool get isLastFragment => (flags & 0x10) != 0;

  /// Creates a [PacketHeader] with the given [version], [flags], [type],
  /// and [payloadLength].
  const PacketHeader({
    this.version = currentVersion,
    this.flags = 0,
    required this.type,
    required this.payloadLength,
  });

  /// Serialises this header to 8 bytes.
  Uint8List encode() {
    final data = ByteData(headerSize);
    data.setUint8(0, version);
    data.setUint8(1, flags);
    data.setUint8(2, type);
    data.setUint8(3, 0); // reserved
    data.setUint32(4, payloadLength, Endian.big);
    return data.buffer.asUint8List();
  }

  /// Decodes from the first 8 bytes of [bytes].
  factory PacketHeader.decode(Uint8List bytes) {
    if (bytes.length < headerSize) {
      throw ArgumentError('Packet too short: ${bytes.length} bytes');
    }
    final data = ByteData.sublistView(bytes);
    return PacketHeader(
      version: data.getUint8(0),
      flags: data.getUint8(1),
      type: data.getUint8(2),
      payloadLength: data.getUint32(4, Endian.big),
    );
  }

  @override
  String toString() =>
      'PacketHeader(v$version, type: $type, '
      'len: $payloadLength, flags: 0x${flags.toRadixString(16)})';
}

// ─── Packet ───────────────────────────────────────────────────────────────────

/// A fully framed network packet: header + payload.
class Packet {
  /// Packet header.
  final PacketHeader header;

  /// Payload bytes.
  final Uint8List payload;

  /// Creates a [Packet] from an existing [header] and [payload].
  const Packet({required this.header, required this.payload});

  /// Builds a data packet (type `0x01`) wrapping [payload].
  factory Packet.data(Uint8List payload, {int flags = 0}) => Packet(
        header: PacketHeader(type: 0x01, payloadLength: payload.length, flags: flags),
        payload: payload,
      );

  /// Builds a control packet with the given [controlType] and [payload].
  factory Packet.control(int controlType, Uint8List payload) => Packet(
        header: PacketHeader(type: controlType, payloadLength: payload.length),
        payload: payload,
      );

  /// Serialises to bytes: header bytes followed by payload bytes.
  Uint8List encode() {
    final result = Uint8List(PacketHeader.headerSize + payload.length);
    result.setAll(0, header.encode());
    result.setAll(PacketHeader.headerSize, payload);
    return result;
  }

  /// Decodes a [Packet] from [bytes] (header + payload).
  factory Packet.decode(Uint8List bytes) {
    final header = PacketHeader.decode(bytes);
    final payload = bytes.sublist(
      PacketHeader.headerSize,
      PacketHeader.headerSize + header.payloadLength,
    );
    return Packet(header: header, payload: payload);
  }

  /// Total encoded size: header (8 bytes) + payload length.
  int get totalSize => PacketHeader.headerSize + payload.length;

  @override
  String toString() =>
      'Packet(type: ${header.type}, payloadLen: ${payload.length})';
}

// ─── Fragment Manager ────────────────────────────────────────────────────────

/// Splits large messages into fragments and reassembles them.
class FragmentManager {
  /// Maximum fragment payload size (MTU minus framing overhead).
  static const int defaultMtu = 1200;

  final Map<String, List<Packet>> _pending = {};

  /// Splits [payload] into MTU-sized [Packet]s with fragment flags set.
  static List<Packet> fragment(Uint8List payload, {int mtu = defaultMtu}) {
    if (payload.length <= mtu) {
      return [Packet.data(payload)];
    }

    final packets = <Packet>[];
    var offset = 0;
    while (offset < payload.length) {
      final end = (offset + mtu).clamp(0, payload.length);
      final isLast = end >= payload.length;
      final chunk = payload.sublist(offset, end);
      packets.add(
        Packet.data(
          chunk,
          flags: 0x08 | (isLast ? 0x10 : 0x00), // isFragment | isLastFragment
        ),
      );
      offset = end;
    }
    return packets;
  }

  /// Feeds one [fragment] for [streamId].
  ///
  /// Returns the fully reassembled payload once all fragments have arrived;
  /// returns `null` if more fragments are still expected.
  Uint8List? feed(String streamId, Packet fragment) {
    final bucket = _pending.putIfAbsent(streamId, () => []);
    bucket.add(fragment);

    if (fragment.header.isLastFragment) {
      final full = _reassemble(bucket);
      _pending.remove(streamId);
      return full;
    }
    return null;
  }

  Uint8List _reassemble(List<Packet> fragments) {
    final totalLength = fragments.fold(0, (s, p) => s + p.payload.length);
    final result = Uint8List(totalLength);
    var offset = 0;
    for (final frag in fragments) {
      result.setAll(offset, frag.payload);
      offset += frag.payload.length;
    }
    return result;
  }
}
