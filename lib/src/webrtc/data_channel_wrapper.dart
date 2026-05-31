/// Abstraction layer over a WebRTC data channel.
///
/// This file provides a transport-agnostic [DataChannelWrapper] that the rest
/// of p2p_dart uses.  In a real Flutter / Dart-native project you would back
/// this with the `flutter_webrtc` or `dart_webrtc` package.  Here the class
/// exposes the exact same API but uses pure-Dart [StreamController]s so that
/// the library compiles and tests run without a native WebRTC engine.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../core/enums.dart';
import '../core/exceptions.dart';
import 'webrtc_config.dart';

// ─── Data Channel Message ─────────────────────────────────────────────────────

/// A message received on a [DataChannelWrapper].
class DataChannelMessage {
  /// Whether the message contains binary data.
  final bool isBinary;

  /// Binary payload (non-null when [isBinary] is `true`).
  final Uint8List? binary;

  /// Text payload (non-null when [isBinary] is `false`).
  final String? text;

  /// Creates a text [DataChannelMessage].
  const DataChannelMessage.text(String this.text)
      : isBinary = false,
        binary = null;

  /// Creates a binary [DataChannelMessage].
  const DataChannelMessage.binary(Uint8List this.binary)
      : isBinary = true,
        text = null;

  /// Returns the JSON-decoded map when [isBinary] is `false`.
  Map<String, dynamic>? get json =>
      text != null ? jsonDecode(text!) as Map<String, dynamic>? : null;

  @override
  String toString() =>
      isBinary ? 'DataChannelMessage.binary(${binary!.length} bytes)'
                : 'DataChannelMessage.text("${text!.length > 80 ? '${text!.substring(0, 80)}…' : text!}")';
}

// ─── Data Channel Wrapper ────────────────────────────────────────────────────

/// Transport-agnostic wrapper around a WebRTC DataChannel.
///
/// Provides:
/// - Typed [send] methods for text and binary data.
/// - A broadcast [onMessage] stream.
/// - A broadcast [onStateChange] stream.
/// - Automatic JSON serialisation / deserialisation.
class DataChannelWrapper {
  // ─── Identity ──────────────────────────────────────────────────────────────

  /// Human-readable label of this channel.
  final String label;

  /// Channel configuration.
  final DataChannelConfig config;

  /// Remote peer ID this channel belongs to.
  final String remotePeerId;

  // ─── State ─────────────────────────────────────────────────────────────────

  DataChannelState _state = DataChannelState.connecting;

  /// Current state of the data channel.
  DataChannelState get state => _state;

  /// Whether the channel is ready to send data.
  bool get isOpen => _state == DataChannelState.open;

  // ─── Streams ───────────────────────────────────────────────────────────────

  final StreamController<DataChannelMessage> _messageController =
      StreamController.broadcast();

  final StreamController<DataChannelState> _stateController =
      StreamController.broadcast();

  /// Stream of incoming messages.
  Stream<DataChannelMessage> get onMessage => _messageController.stream;

  /// Stream of state transitions.
  Stream<DataChannelState> get onStateChange => _stateController.stream;

  // ─── Stats ─────────────────────────────────────────────────────────────────

  int _messagesSent = 0;
  int _messagesReceived = 0;
  int _bytesSent = 0;
  int _bytesReceived = 0;

  /// Total messages sent on this channel.
  int get messagesSent => _messagesSent;

  /// Total messages received on this channel.
  int get messagesReceived => _messagesReceived;

  /// Total bytes sent.
  int get bytesSent => _bytesSent;

  /// Total bytes received.
  int get bytesReceived => _bytesReceived;

  // ─── Constructor ───────────────────────────────────────────────────────────

  /// Creates a [DataChannelWrapper].
  DataChannelWrapper({
    required this.label,
    required this.remotePeerId,
    DataChannelConfig? config,
  }) : config = config ?? const DataChannelConfig();

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  /// Marks the channel as open (called by [WebRTCManager] when the native
  /// channel fires `onOpen`).
  void markOpen() => _setState(DataChannelState.open);

  /// Marks the channel as closed.
  void markClosed() => _setState(DataChannelState.closed);

  // ─── Sending ──────────────────────────────────────────────────────────────

  /// Sends a text string.
  void sendText(String text) {
    _assertOpen();
    // In a real implementation, forward to RTCDataChannel.send().
    _messagesSent++;
    _bytesSent += text.length;
  }

  /// Sends raw bytes.
  void sendBinary(Uint8List bytes) {
    _assertOpen();
    _messagesSent++;
    _bytesSent += bytes.length;
  }

  /// Serialises [payload] to JSON and sends it as a text message.
  void sendJson(Map<String, dynamic> payload) {
    sendText(jsonEncode(payload));
  }

  // ─── Receiving (called by the transport layer) ───────────────────────────

  /// Delivers an incoming [message] to subscribers on [onMessage].
  ///
  /// Called by the underlying transport when a message arrives.
  void receive(DataChannelMessage message) {
    if (_state == DataChannelState.closed) return;
    _messagesReceived++;
    _bytesReceived += message.isBinary
        ? message.binary!.length
        : message.text!.length;
    _messageController.add(message);
  }

  // ─── Close ────────────────────────────────────────────────────────────────

  /// Closes this data channel.
  Future<void> close() async {
    if (_state == DataChannelState.closed) return;
    _setState(DataChannelState.closing);
    _setState(DataChannelState.closed);
    await _messageController.close();
    await _stateController.close();
  }

  // ─── Stats ────────────────────────────────────────────────────────────────

  /// Returns a snapshot of channel statistics.
  Map<String, dynamic> stats() => {
        'label': label,
        'state': state.name,
        'messagesSent': _messagesSent,
        'messagesReceived': _messagesReceived,
        'bytesSent': _bytesSent,
        'bytesReceived': _bytesReceived,
      };

  // ─── Private Helpers ────────────────────────────────────────────────────

  void _setState(DataChannelState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  void _assertOpen() {
    if (!isOpen) {
      throw DataChannelException(
        'DataChannel "$label" to $remotePeerId is not open '
        '(state: ${_state.name})',
      );
    }
  }

  @override
  String toString() =>
      'DataChannelWrapper(label: $label, '
      'peer: ${remotePeerId.substring(0, 8)}…, '
      'state: ${_state.name})';
}
