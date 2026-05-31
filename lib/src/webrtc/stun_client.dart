/// Pure-Dart STUN client (RFC 5389).
///
/// Performs a Binding Request to discover the public (reflexive) IP and port
/// of the local socket without requiring a native WebRTC runtime.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math';

// ─── STUN Constants ───────────────────────────────────────────────────────────

const int _stunMagicCookie = 0x2112A442;
const int _stunBindingRequest = 0x0001;
const int _stunBindingResponse = 0x0101;
const int _stunBindingError = 0x0111;

const int _stunAttrMappedAddress = 0x0001;
const int _stunAttrXorMappedAddress = 0x0020;

const Duration _defaultTimeout = Duration(seconds: 5);

// ─── STUN Response ────────────────────────────────────────────────────────────

/// The result of a successful STUN Binding Request.
class StunResponse {
  /// Public IP address seen by the STUN server.
  final InternetAddress publicAddress;

  /// Public port seen by the STUN server.
  final int publicPort;

  /// Creates a [StunResponse].
  const StunResponse({
    required this.publicAddress,
    required this.publicPort,
  });

  /// Convenience string representation of the mapped address.
  String get mappedAddress => '${publicAddress.address}:$publicPort';

  @override
  String toString() => 'StunResponse($mappedAddress)';
}

// ─── STUN Client ─────────────────────────────────────────────────────────────

/// Minimal RFC 5389 STUN client.
///
/// Sends a Binding Request over UDP and parses the XOR-MAPPED-ADDRESS
/// attribute from the response.
///
/// Usage:
/// ```dart
/// final client = StunClient('stun.l.google.com');
/// final response = await client.discoverPublicAddress();
/// print(response.mappedAddress);
/// ```
class StunClient {
  /// STUN server hostname.
  final String host;

  /// STUN server port (default 3478).
  final int port;

  /// Request timeout.
  final Duration timeout;

  /// Creates a [StunClient].
  const StunClient(
    this.host, {
    this.port = 3478,
    this.timeout = _defaultTimeout,
  });

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Performs a STUN Binding Request and returns the public address.
  ///
  /// Throws a [TimeoutException] if no response is received within [timeout].
  /// Throws a [StunException] if the server returns an error response.
  Future<StunResponse> discoverPublicAddress() async {
    // Resolve hostname.
    final addresses = await InternetAddress.lookup(host);
    if (addresses.isEmpty) {
      throw StunException('Cannot resolve STUN server: $host');
    }
    final serverAddress = addresses.first;

    // Bind a local UDP socket.
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      0,
    );

    try {
      final transactionId = _generateTransactionId();
      final request = _buildBindingRequest(transactionId);

      // Send the request.
      socket.send(request, serverAddress, port);

      // Wait for the response.
      final completer = Completer<StunResponse>();

      socket.listen((RawSocketEvent event) {
        if (event != RawSocketEvent.read) return;
        final datagram = socket.receive();
        if (datagram == null) return;

        try {
          final response = _parseResponse(datagram.data, transactionId);
          if (!completer.isCompleted) completer.complete(response);
        } catch (e) {
          if (!completer.isCompleted) completer.completeError(e);
        }
      });

      return await completer.future.timeout(
        timeout,
        onTimeout: () => throw TimeoutException(
          'STUN request to $host:$port timed out',
          timeout,
        ),
      );
    } finally {
      socket.close();
    }
  }

  // ─── Message Building ────────────────────────────────────────────────────

  Uint8List _generateTransactionId() {
    final rng = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(12, (_) => rng.nextInt(256)),
    );
  }

  Uint8List _buildBindingRequest(Uint8List transactionId) {
    final buffer = ByteData(20);

    // Message type: Binding Request
    buffer.setUint16(0, _stunBindingRequest, Endian.big);
    // Message length: 0 (no attributes)
    buffer.setUint16(2, 0, Endian.big);
    // Magic Cookie
    buffer.setUint32(4, _stunMagicCookie, Endian.big);
    // Transaction ID (12 bytes)
    final result = Uint8List(20);
    result.setAll(0, buffer.buffer.asUint8List());
    result.setAll(8, transactionId);
    return result;
  }

  // ─── Response Parsing ────────────────────────────────────────────────────

  StunResponse _parseResponse(Uint8List data, Uint8List transactionId) {
    if (data.length < 20) {
      throw StunException('Response too short: ${data.length} bytes');
    }

    final view = ByteData.sublistView(data);
    final messageType = view.getUint16(0, Endian.big);

    if (messageType == _stunBindingError) {
      throw StunException('STUN server returned error response');
    }
    if (messageType != _stunBindingResponse) {
      throw StunException('Unexpected message type: 0x${messageType.toRadixString(16)}');
    }

    // Parse attributes starting at byte 20.
    int offset = 20;
    while (offset < data.length - 4) {
      final attrType = view.getUint16(offset, Endian.big);
      final attrLength = view.getUint16(offset + 2, Endian.big);
      offset += 4;

      if (attrType == _stunAttrXorMappedAddress ||
          attrType == _stunAttrMappedAddress) {
        return _parseMappedAddress(
          data,
          offset,
          xor: attrType == _stunAttrXorMappedAddress,
        );
      }

      offset += attrLength + (attrLength % 4 != 0 ? 4 - attrLength % 4 : 0);
    }

    throw StunException('No MAPPED-ADDRESS attribute in STUN response');
  }

  StunResponse _parseMappedAddress(
    Uint8List data,
    int offset, {
    required bool xor,
  }) {
    final view = ByteData.sublistView(data);
    // Skip reserved byte at offset.
    final family = view.getUint8(offset + 1);
    int rawPort = view.getUint16(offset + 2, Endian.big);
    int port;

    if (xor) {
      port = rawPort ^ (_stunMagicCookie >> 16);
    } else {
      port = rawPort;
    }

    InternetAddress address;
    if (family == 0x01) {
      // IPv4
      final rawIp = view.getUint32(offset + 4, Endian.big);
      final ip = xor ? rawIp ^ _stunMagicCookie : rawIp;
      address = InternetAddress(
        '${(ip >> 24) & 0xFF}.'
        '${(ip >> 16) & 0xFF}.'
        '${(ip >> 8) & 0xFF}.'
        '${ip & 0xFF}',
      );
    } else {
      // IPv6 — simplified
      address = InternetAddress('::1');
    }

    return StunResponse(publicAddress: address, publicPort: port);
  }
}

// ─── STUN Exception ──────────────────────────────────────────────────────────

/// Thrown when a STUN operation fails.
class StunException implements Exception {
  /// Error message.
  final String message;

  /// Creates a [StunException].
  const StunException(this.message);

  @override
  String toString() => 'StunException: $message';
}

// ─── STUN Pool ────────────────────────────────────────────────────────────────

/// Queries multiple STUN servers concurrently and returns the first
/// successful response.
class StunPool {
  final List<StunClient> _clients;

  /// Creates a [StunPool] from a list of server [hosts].
  StunPool(List<String> hosts)
      : _clients = hosts.map((h) => StunClient(h)).toList();

  /// Queries all servers concurrently and returns the first result.
  ///
  /// Throws if all servers fail.
  Future<StunResponse> discoverPublicAddress() async {
    final completer = Completer<StunResponse>();
    var failures = 0;

    for (final client in _clients) {
      client.discoverPublicAddress().then((response) {
        if (!completer.isCompleted) completer.complete(response);
      }).catchError((Object error) {
        failures++;
        if (failures == _clients.length && !completer.isCompleted) {
          completer.completeError(
            const StunException('All STUN servers failed'),
          );
        }
      });
    }

    return completer.future;
  }
}
