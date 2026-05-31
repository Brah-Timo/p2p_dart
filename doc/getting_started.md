# Getting Started with p2p_dart

`p2p_dart` is a Dart/Flutter library for building peer-to-peer (P2P) applications using a Kademlia-based Distributed Hash Table (DHT) for peer discovery and WebRTC data channels for encrypted, direct connections.

---

## Table of Contents

1. [Requirements](#requirements)
2. [Installation](#installation)
3. [Quick Start](#quick-start)
4. [Creating a Node](#creating-a-node)
5. [Connecting to Peers](#connecting-to-peers)
6. [Sending Messages](#sending-messages)
7. [Receiving Messages](#receiving-messages)
8. [Shutting Down](#shutting-down)
9. [Full Example](#full-example)
10. [Next Steps](#next-steps)

---

## Requirements

- Dart SDK `>=3.0.0` or Flutter `>=3.10.0`
- Dependencies (added automatically via `pub get`):
  - `rxdart` — reactive stream utilities
  - `pointycastle` — cryptography
  - `uuid` — unique ID generation
  - `crypto` — SHA-1 / HMAC hashing

---

## Installation

Add `p2p_dart` to your `pubspec.yaml`:

```yaml
dependencies:
  p2p_dart:
    path: ../p2p_dart   # local path, or use pub.dev version once published
```

Then run:

```bash
dart pub get
# or for Flutter projects:
flutter pub get
```

---

## Quick Start

```dart
import 'package:p2p_dart/p2p_dart.dart';

void main() async {
  // 1. Create and initialise a node.
  final node = P2PNode(
    config: P2PConfig(
      bootstrapPeers: ['<known-peer-hex-id>'],
    ),
  );
  await node.initialize();

  print('Online as: ${node.peerId}');

  // 2. Listen for incoming messages.
  node.eventBus.on<MessageReceivedEvent>((event) {
    print('Message from ${event.senderId}: ${event.data}');
  });

  // 3. Connect to a remote peer and send data.
  await node.connect('<remote-peer-id>');
  await node.send('<remote-peer-id>', {'hello': 'world'});

  // 4. Clean up.
  await node.stop();
}
```

---

## Creating a Node

A `P2PNode` is the central object. It manages the DHT, WebRTC connections, and the event bus.

```dart
final node = P2PNode(
  config: P2PConfig(
    // Optional: pass bootstrap peers so the node can join an existing network.
    bootstrapPeers: [
      'aabbccdd...40hexchars...',
    ],

    // Optional: fix a peer ID (must be exactly 40 hex characters).
    // If omitted, a random 160-bit ID is generated.
    peerId: null,

    // Optional: human-readable name advertised to other peers.
    displayName: 'Alice',

    // Optional: WebRTC / STUN settings.
    webrtc: WebRTCConfig(
      stunServers: [
        StunServerConfig('stun.l.google.com'),
      ],
    ),

    // Optional: security settings.
    security: SecurityConfig(
      enforceEncryption: true,
      requireAuthentication: false,
    ),

    // Optional: enable verbose logging.
    logging: LoggingConfig(verbose: true),
  ),
);

// initialize() starts the DHT, WebRTC subsystem, and bootstrapping.
await node.initialize();
```

After `initialize()`, `node.status` is `NodeStatus.online` and `node.peerId` is set.

---

## Connecting to Peers

```dart
// Connect to a specific peer by its 40-char hex ID.
try {
  final connection = await node.connect('aabbccdd...40hexchars...');
  print('Connected! State: ${connection.state}');
} on PeerNotFoundException catch (e) {
  print('Peer not found in DHT: $e');
} on ConnectionTimeoutException catch (e) {
  print('Timed out: $e');
}

// Check if already connected.
final alreadyConnected = node.isConnectedTo('<peer-id>');

// Disconnect.
await node.disconnect('<peer-id>');
```

---

## Sending Messages

```dart
// Send a JSON map to one peer.
await node.send('<peer-id>', {
  'type': 'chat',
  'text': 'Hello, peer!',
  'timestamp': DateTime.now().toIso8601String(),
});

// Send a plain text string.
await node.sendText('<peer-id>', 'Hello!');

// Broadcast to ALL currently connected peers.
await node.broadcast({
  'type': 'announcement',
  'text': 'Node is online',
});

// Send to a subset of peers.
await node.sendToMany(
  ['<peer-id-1>', '<peer-id-2>'],
  {'type': 'group', 'msg': 'Hi group'},
);
```

---

## Receiving Messages

Listen to the `EventBus` for typed events:

```dart
// All incoming data messages.
node.eventBus.on<MessageReceivedEvent>((event) {
  print('From: ${event.senderId}');
  print('Data: ${event.data}');
});

// Peer connected / disconnected.
node.eventBus.on<PeerConnectedEvent>((event) {
  print('Peer joined: ${event.peerId}');
});

node.eventBus.on<PeerLeftEvent>((event) {
  print('Peer left: ${event.peerId} (reason: ${event.reason})');
});

// Node status changes.
node.onStatusChange.listen((status) {
  print('Node status: $status');
});
```

You can also register typed message handlers on a specific connection:

```dart
final connection = node.connectionTo('<peer-id>');
connection?.on(MessageType.data, (message) async {
  print('Data message: ${message.payload}');
});
```

---

## Shutting Down

```dart
await node.stop();
// This closes all WebRTC connections, stops the DHT, and emits NodeStoppedEvent.
```

---

## Full Example

See [`example/simple_chat.dart`](../example/simple_chat.dart) for a complete interactive CLI chat application demonstrating:

- Node creation and initialization
- Bootstrap peer connection
- Connecting to a remote peer
- Sending / receiving chat messages
- Broadcasting to all peers
- Graceful shutdown

Run it with:

```bash
dart run example/simple_chat.dart [optional-bootstrap-peer-id]
```

---

## Next Steps

| Topic | Document |
|-------|----------|
| System architecture | [architecture.md](architecture.md) |
| DHT internals | [dht.md](dht.md) |
| WebRTC internals | [webrtc.md](webrtc.md) |
| Security & authentication | [security.md](security.md) |
| Networking & messages | [networking.md](networking.md) |
| Configuration reference | [configuration.md](configuration.md) |
| Full API reference | [api_reference.md](api_reference.md) |
