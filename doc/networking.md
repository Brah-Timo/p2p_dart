# Networking & Messaging

This document covers how `p2p_dart` encodes, delivers, and routes messages between peers.

---

## Table of Contents

1. [Message Format](#message-format)
2. [MessageType Enum](#messagetype-enum)
3. [Encoding / Decoding](#encoding--decoding)
4. [Transport Layer](#transport-layer)
5. [Message Handler Pipeline](#message-handler-pipeline)
6. [Packet Framing](#packet-framing)
7. [Connection Lifecycle](#connection-lifecycle)
8. [Heartbeat](#heartbeat)
9. [Send Buffer & Back-pressure](#send-buffer--back-pressure)
10. [Reliable Mode & ACKs](#reliable-mode--acks)
11. [Binary Payloads](#binary-payloads)
12. [Stream Extensions](#stream-extensions)

---

## Message Format

All data exchanged between peers is wrapped in a `P2PMessage`:

```json
{
  "type": "data",
  "correlationId": "1gk3a7",
  "senderId": "aabbcc...40chars...",
  "timestamp": 1717200000000,
  "protocolVersion": "1.0.0",
  "payload": {
    "text": "Hello, peer!"
  }
}
```

### Fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | `String` (enum name) | Message classification (`data`, `ping`, etc.) |
| `correlationId` | `String` | Unique token for request/response matching |
| `senderId` | `String` | 40-char hex ID of the originating peer |
| `timestamp` | `int` | Unix milliseconds at creation |
| `protocolVersion` | `String` | Sender's protocol version |
| `payload` | `Map?` | JSON application payload |
| `binaryPayload` | `String?` | Base64-encoded binary data (optional) |

---

## MessageType Enum

```dart
enum MessageType {
  // Application
  data,          // Application data payload

  // Keep-alive
  ping,          // Heartbeat request
  pong,          // Heartbeat response

  // Reliability
  ack,           // Acknowledgement

  // Lifecycle
  goodbye,       // Graceful disconnect notification
  error,         // Error notification

  // DHT RPC (internal)
  dhtPing,
  dhtPong,
  dhtFindNode,
  dhtFindValue,
  dhtStore,
}
```

Application code sends and receives messages with `type == MessageType.data`. All other types are handled internally by the library.

---

## Encoding / Decoding

```dart
// Create a data message.
final msg = P2PMessage.data('senderId', {'hello': 'world'});

// Encode to JSON string.
final jsonStr = msg.encode();

// Encode to UTF-8 bytes.
final bytes = msg.encodeBytes();

// Decode from JSON string.
final decoded = P2PMessage.decode(jsonStr);

// Decode from bytes.
final decoded = P2PMessage.decodeBytes(bytes);

// From / to JSON map.
final map = msg.toJson();
final msg2 = P2PMessage.fromJson(map);
```

Binary payloads are automatically base64-encoded in the JSON and decoded on the receiving side.

---

## Transport Layer

`TransportLayer` sits between the `Connection` and `DataChannelWrapper`. It manages:

- **Outbound send queue** — messages are queued and flushed immediately.
- **Back-pressure** — `TransportException` thrown if the queue exceeds `maxQueueDepth` (default 1000).
- **Packet framing** — wraps encoded messages in a `Packet` before transmission.
- **Optional ACK tracking** — see [Reliable Mode & ACKs](#reliable-mode--acks).

### Callbacks

```dart
final transport = TransportLayer(
  peerId: remotePeerId,
  maxQueueDepth: 1000,
  ackTimeout: Duration(seconds: 5),
  requireAcks: false,
);

// Wire outbound path.
transport.onSendBytes = (bytes) => channel.sendBinary(bytes);

// Wire inbound path.
channel.onMessage.listen((msg) => transport.receive(msg.binary!));

// Access inbound message stream.
transport.inbound.listen((message) {
  print('Received: $message');
});

transport.start();
```

---

## Message Handler Pipeline

`MessageHandler` provides a **middleware chain** and **typed handler dispatch**:

```dart
final handler = MessageHandler();

// Global middleware (runs for every message).
handler.use((message, next) async {
  print('Before: ${message.type}');
  await next(message);
  print('After: ${message.type}');
});

// Typed handler for a specific MessageType.
handler.on(MessageType.data, (message) async {
  final text = message.payload?['text'];
  print('Data: $text');
});

// Dispatch a message through the pipeline.
await handler.dispatch(incomingMessage);
```

**Order of execution:**

1. All middleware in registration order.
2. The typed handler for `message.type` (if registered).

`P2PNode` exposes a global `messageHandler` and each `Connection` has its own `MessageHandler`, allowing fine-grained per-connection routing.

---

## Packet Framing

Raw bytes on the wire are framed using a thin `Packet` wrapper:

```
┌──────────┬──────────┬──────────────────┐
│  version │   type   │     payload      │
│  1 byte  │  1 byte  │  N bytes         │
└──────────┴──────────┴──────────────────┘
```

- `version` — protocol version byte (currently `1`).
- `type` — `0x01` for data, `0x02` for control.
- `payload` — UTF-8 JSON of the `P2PMessage`.

Packets are decoded in `TransportLayer.receive(bytes)`.

---

## Connection Lifecycle

```
[idle]
  │  DataChannelWrapper opens
  ▼
[connecting]
  │  DataChannelState.open
  ▼
[connected]  ← heartbeat timer starts
  │
  │  DataChannelState.closing
  ▼
[disconnected]
  │  DataChannelState.closed
  ▼
[closed]     ← heartbeat timer cancelled
```

State changes are broadcast via `connection.onStateChange`:

```dart
connection.onStateChange.listen((state) {
  if (state == ConnectionState.closed) {
    print('Connection to ${connection.remotePeerId} closed');
  }
});
```

---

## Heartbeat

`Connection` sends periodic `PING` messages to detect silently dead connections:

1. Every `heartbeatInterval` (default 30 s) a `P2PMessage.ping` is sent.
2. The remote peer replies immediately with `P2PMessage.pong`.
3. The last pong timestamp is tracked for RTT estimation in `ConnectionStats`.

If the remote peer goes silent (no pong received), the connection will eventually be detected as dead when the underlying WebRTC data channel closes.

---

## Send Buffer & Back-pressure

```
node.send(peerId, data)
  │
  ▼
TransportLayer.send(message)  ←── throws TransportException if queue full
  │
  ├─ _sendQueue: List<_QueueItem>   (pending transmit)
  └─ _awaitingAck: Map<String, _QueueItem>  (if requireAcks: true)
```

- `sendBufferSize` in `PerformanceConfig` controls `maxQueueDepth` (default 1000).
- When the queue is full, `send()` throws `TransportException` immediately — it does **not** block.
- Application code should handle this with retry logic or flow control.

---

## Reliable Mode & ACKs

By default, `requireAcks` is `false` (unreliable/best-effort mode). Set `requireAcks: true` when constructing `TransportLayer` to enable acknowledgements:

```
Sender                         Receiver
  │── DATA message ──────────►  │
  │                             │── ACK (correlationId) ─► Sender
  │   (if no ACK within 5 s)   │
  │── DATA message (retry 1) ►  │
  │── DATA message (retry 2) ►  │
  │   (if still no ACK after 3 attempts)
  └── completer.completeError(TransportException)
```

- Retransmissions are checked every 2 seconds by `_checkRetransmits`.
- Maximum 3 attempts before failing with `TransportException`.

---

## Binary Payloads

For sending raw bytes (e.g., file chunks):

```dart
// Sender
final connection = node.connectionTo(peerId);
await connection?.sendBinary(Uint8List.fromList([0x01, 0x02, 0x03]));

// Receiver — listen on onData stream
connection?.onData.listen((msg) {
  if (msg.binaryPayload != null) {
    final bytes = msg.binaryPayload!;
    // process bytes...
  }
});
```

Large payloads can be split using `Chunker` and reassembled:

```dart
// Split 10 MB file into 64 KB chunks.
final chunks = Chunker.split(fileBytes, 65536);
for (final chunk in chunks) {
  await connection.sendBinary(chunk);
}

// Reassemble.
final original = Chunker.join(receivedChunks);
```

---

## Stream Extensions

`P2PStreamExtensions` adds utilities to any `Stream<T>`:

```dart
// Get first message of a specific type.
final firstData = await node.eventBus
    .stream<MessageReceivedEvent>()
    .firstOfType<MessageReceivedEvent>();

// Batch incoming messages into groups of 10.
connection.onData.batch(10).listen((batch) {
  print('Batch of ${batch.length} messages');
});

// Debounce rapid events (wait 200ms of silence).
connection.onStateChange.debounce(Duration(milliseconds: 200)).listen(print);

// Throttle to at most one event per second.
node.eventBus.stream<MessageReceivedEvent>()
    .throttle(Duration(seconds: 1))
    .listen((e) => print('Rate-limited: ${e.data}'));

// Emit (prev, curr) pairs.
connection.onStateChange.pairwise().listen((pair) {
  print('State: ${pair.$1} → ${pair.$2}');
});
```
