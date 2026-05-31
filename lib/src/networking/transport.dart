/// Reliable and unreliable transport abstractions.
library;

import 'dart:async';
import 'dart:typed_data';

import '../core/enums.dart';
import '../core/exceptions.dart';
import '../utils/logger.dart';
import 'message.dart';
import 'packet.dart';

// ─── Send Queue Item ─────────────────────────────────────────────────────────

class _QueueItem {
  final P2PMessage message;
  final Completer<void> completer;
  int attempts = 0;

  _QueueItem(this.message) : completer = Completer<void>();
}

// ─── Transport Layer ─────────────────────────────────────────────────────────

/// Manages reliable message delivery over a [DataChannelWrapper].
///
/// Features:
/// - Outbound send queue with configurable depth.
/// - Optional message acknowledgement tracking.
/// - Automatic retransmission on timeout (reliable mode).
/// - Back-pressure: [send] throws [TransportException] when the queue is full.
class TransportLayer {
  // ─── Config ────────────────────────────────────────────────────────────────

  final String _peerId;
  final int _maxQueueDepth;
  final Duration _ackTimeout;
  final bool _requireAcks;
  final P2PLogger _log;

  // ─── State ─────────────────────────────────────────────────────────────────

  final List<_QueueItem> _sendQueue = [];
  final Map<String, _QueueItem> _awaitingAck = {};

  bool _running = false;
  Timer? _retransmitTimer;

  // ─── Callbacks ─────────────────────────────────────────────────────────────

  /// Called to actually transmit serialised bytes.
  void Function(Uint8List bytes)? onSendBytes;

  // ─── Streams ───────────────────────────────────────────────────────────────

  final StreamController<P2PMessage> _inboundController =
      StreamController.broadcast();

  /// Stream of inbound [P2PMessage]s from the remote peer.
  Stream<P2PMessage> get inbound => _inboundController.stream;

  // ─── Constructor ───────────────────────────────────────────────────────────

  /// Creates a [TransportLayer] for [_peerId].
  TransportLayer({
    required String peerId,
    int maxQueueDepth = 1000,
    Duration ackTimeout = const Duration(seconds: 5),
    bool requireAcks = false,
    P2PLogger? logger,
  })  : _peerId = peerId,
        _maxQueueDepth = maxQueueDepth,
        _ackTimeout = ackTimeout,
        _requireAcks = requireAcks,
        _log = logger ?? P2PLogger('Transport[$peerId]');

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  /// Starts the transport.
  void start() {
    _running = true;
    if (_requireAcks) {
      _retransmitTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _checkRetransmits(),
      );
    }
  }

  /// Stops the transport and cancels all pending sends.
  void stop() {
    _running = false;
    _retransmitTimer?.cancel();

    for (final item in [..._sendQueue, ..._awaitingAck.values]) {
      if (!item.completer.isCompleted) {
        item.completer.completeError(
          const TransportException('Transport stopped'),
        );
      }
    }

    _sendQueue.clear();
    _awaitingAck.clear();
    _inboundController.close();
  }

  // ─── Sending ──────────────────────────────────────────────────────────────

  /// Enqueues [message] for delivery.
  ///
  /// Throws [TransportException] if the queue is full.
  Future<void> send(P2PMessage message) {
    if (!_running) {
      throw const TransportException('Transport is not running');
    }
    if (_sendQueue.length >= _maxQueueDepth) {
      throw TransportException(
        'Send queue full (depth: $_maxQueueDepth) for peer $_peerId',
      );
    }

    final item = _QueueItem(message);
    _sendQueue.add(item);
    _flush();
    return item.completer.future;
  }

  // ─── Receiving ────────────────────────────────────────────────────────────

  /// Delivers raw [bytes] received from the remote peer.
  void receive(Uint8List bytes) {
    try {
      final packet = Packet.decode(bytes);
      final message = P2PMessage.decodeBytes(packet.payload);
      _handleInbound(message);
    } catch (e) {
      _log.warning('Failed to decode inbound packet: $e');
    }
  }

  // ─── Private ─────────────────────────────────────────────────────────────

  void _flush() {
    while (_sendQueue.isNotEmpty) {
      final item = _sendQueue.removeAt(0);
      _transmit(item);
    }
  }

  void _transmit(_QueueItem item) {
    item.attempts++;
    try {
      final bytes = Packet.data(item.message.encodeBytes()).encode();
      onSendBytes?.call(bytes);

      if (_requireAcks) {
        _awaitingAck[item.message.correlationId] = item;
        Timer(_ackTimeout, () => _onAckTimeout(item));
      } else {
        if (!item.completer.isCompleted) item.completer.complete();
      }
    } catch (e) {
      if (!item.completer.isCompleted) {
        item.completer.completeError(TransportException(e.toString()));
      }
    }
  }

  void _handleInbound(P2PMessage message) {
    // Handle ACKs internally.
    if (message.type == MessageType.ack) {
      final pending = _awaitingAck.remove(message.correlationId);
      if (pending != null && !pending.completer.isCompleted) {
        pending.completer.complete();
      }
      return;
    }

    // Send ACK if required.
    if (_requireAcks && !message.isControl) {
      final ack = P2PMessage.ack(message.senderId, message.correlationId);
      final bytes = Packet.data(ack.encodeBytes()).encode();
      onSendBytes?.call(bytes);
    }

    _inboundController.add(message);
  }

  void _checkRetransmits() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final item in _awaitingAck.values) {
      final age = now - item.message.timestamp;
      if (age > _ackTimeout.inMilliseconds && item.attempts < 3) {
        _log.debug('Retransmitting message ${item.message.correlationId}');
        _transmit(item);
      }
    }
  }

  void _onAckTimeout(_QueueItem item) {
    if (!_awaitingAck.containsKey(item.message.correlationId)) return;
    if (item.attempts >= 3) {
      _awaitingAck.remove(item.message.correlationId);
      if (!item.completer.isCompleted) {
        item.completer.completeError(
          TransportException(
            'Message unacknowledged after ${item.attempts} attempts',
          ),
        );
      }
    }
  }
}
