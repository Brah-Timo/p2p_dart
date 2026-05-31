# Architecture

This document describes the high-level design, component layout, and data-flow of the `p2p_dart` library.

---

## Table of Contents

1. [Overview](#overview)
2. [Component Map](#component-map)
3. [Layer Descriptions](#layer-descriptions)
4. [Data Flow](#data-flow)
5. [Lifecycle](#lifecycle)
6. [Design Principles](#design-principles)
7. [Directory Structure](#directory-structure)

---

## Overview

`p2p_dart` is structured as a set of loosely coupled subsystems wired together by `P2PNode`:

```
┌──────────────────────────────────────────────────────────┐
│                        P2PNode                           │
│                                                          │
│  ┌───────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │ DHTNetwork│  │ WebRTCManager│  │  ChannelManager  │  │
│  └─────┬─────┘  └──────┬───────┘  └────────┬─────────┘  │
│        │               │                   │             │
│        │   RPC via     │  Signalling        │  Connections│
│        │   Connections │  via DHT           │             │
│        └───────────────┴───────────────────┘             │
│                         ▼                               │
│                   EventBus / Streams                    │
└──────────────────────────────────────────────────────────┘
```

---

## Component Map

| Component | File | Role |
|-----------|------|------|
| `P2PNode` | `lib/src/core/p2p_node.dart` | Orchestrator; public API entry point |
| `P2PConfig` | `lib/src/core/p2p_config.dart` | Immutable configuration bundle |
| `DHTNetwork` | `lib/src/dht/dht_network.dart` | Kademlia DHT — peer discovery & key-value store |
| `RoutingTable` | `lib/src/dht/routing_table.dart` | 160-bucket Kademlia routing table |
| `Kademlia` | `lib/src/dht/kademlia.dart` | XOR-metric utilities, ID generation |
| `KBucket` | `lib/src/dht/bucket.dart` | Single Kademlia k-bucket |
| `WebRTCManager` | `lib/src/webrtc/webrtc_manager.dart` | SDP negotiation, ICE, channel management |
| `DataChannelWrapper` | `lib/src/webrtc/data_channel_wrapper.dart` | Thin wrapper over a WebRTC data channel |
| `ChannelManager` | `lib/src/core/channel_manager.dart` | Registry of active `Connection` objects |
| `Connection` | `lib/src/core/connection.dart` | Single peer connection (transport + heartbeat) |
| `TransportLayer` | `lib/src/networking/transport.dart` | Reliable send queue + ACK tracking |
| `P2PMessage` | `lib/src/networking/message.dart` | Protocol message type |
| `MessageHandler` | `lib/src/networking/message_handler.dart` | Middleware + typed-handler dispatch |
| `EventBus` | `lib/src/events/event_bus.dart` | Application-level pub/sub event system |
| `AuthManager` | `lib/src/security/auth_manager.dart` | HMAC challenge-response authentication |
| `CryptoUtils` | `lib/src/security/crypto_utils.dart` | AES-GCM encryption, HMAC, key derivation |
| `P2PLogger` | `lib/src/utils/logger.dart` | Structured logging with levels |
| `GrowingBuffer` | `lib/src/utils/buffer_manager.dart` | Dynamic byte buffer |
| `Chunker` | `lib/src/utils/buffer_manager.dart` | Large-payload chunker/reassembler |

---

## Layer Descriptions

### 1. Core Layer (`lib/src/core/`)

The core layer contains:

- **`P2PNode`** — the public-facing entry point. It creates, wires, and orchestrates all subsystems.
- **`P2PConfig`** — a plain data object holding all configuration (DHT, WebRTC, security, performance, logging).
- **`Connection`** — wraps a single `DataChannelWrapper` with a `TransportLayer` for reliable delivery and heartbeat keep-alive.
- **`ChannelManager`** — a registry that maps peer IDs to `Connection` objects, enforcing `maxConnections`.
- **`Enums`** — shared enum types (`MessageType`, `ConnectionState`, `NodeStatus`, etc.).
- **`Exceptions`** — the typed exception hierarchy.
- **`PeerInfo`** — a value object describing a known peer (ID, addresses, display name).

### 2. DHT Layer (`lib/src/dht/`)

Implements the Kademlia distributed hash table:

- **`DHTNetwork`** — manages the routing table, runs iterative lookups, handles STORE / FIND_NODE / FIND_VALUE RPCs, and runs periodic refresh and republication timers.
- **`RoutingTable`** — maintains up to 160 k-buckets. Buckets are lazily split when full.
- **`KBucket`** — holds up to *k* (default 20) `PeerInfo` entries plus a replacement cache.
- **`Kademlia`** — pure-function helpers: XOR distance, bucket index, ID generation, SHA-1 content addressing.
- **`DHTConfig`** — DHT-specific tuning (bucket size, alpha, replication factor, TTL, etc.).

### 3. WebRTC Layer (`lib/src/webrtc/`)

Implements WebRTC peer connection management:

- **`WebRTCManager`** — creates SDP offers/answers, gathers ICE candidates, tracks pending offers, and produces `DataChannelWrapper` instances.
- **`DataChannelWrapper`** — provides `sendBinary`, `sendJson`, and incoming message streams over a data channel.
- **`IceConfiguration`** / **`IceCandidate`** — ICE candidate model and STUN/TURN configuration.
- **`WebRTCConfig`** — STUN/TURN servers, timeout settings, channel configuration.

### 4. Networking Layer (`lib/src/networking/`)

Handles message serialisation and delivery:

- **`P2PMessage`** — the single protocol message type. JSON-serialisable with a `MessageType`, correlation ID, sender ID, timestamp, and payload.
- **`TransportLayer`** — a send queue (`List<_QueueItem>`) with optional ACK tracking and retransmission (up to 3 attempts).
- **`MessageHandler`** — a middleware chain + typed dispatch table for routing inbound messages.
- **`Packet`** — a thin framing wrapper around raw bytes for the wire format.

### 5. Security Layer (`lib/src/security/`)

- **`AuthManager`** — issues HMAC-SHA256 challenge-response tokens and verifies peer identities.
- **`CryptoUtils`** — AES-256-GCM encryption/decryption, HMAC-SHA256, constant-time comparison, key derivation, random-byte generation.

### 6. Events (`lib/src/events/`)

- **`EventBus`** — a generic typed pub/sub bus. Listeners are called synchronously and are automatically removed when cancelled.
- **Events** — all event classes: `NodeStartedEvent`, `NodeStoppedEvent`, `PeerConnectedEvent`, `PeerLeftEvent`, `MessageReceivedEvent`, `DHTBootstrappedEvent`, etc.

### 7. Extensions (`lib/src/extensions/`)

- **`P2PStreamExtensions`** — `asBroadcast()`, `firstOfType<S>()`, `batch(n)`, `debounce(d)`, `throttle(d)`, `pairwise()`.

---

## Data Flow

### Outbound Message

```
app code
  │  node.send(peerId, data)
  ▼
P2PNode
  │  channelManager.get(peerId)
  ▼
Connection.send(data)
  │  P2PMessage.data(localPeerId, data)
  ▼
TransportLayer.send(message)
  │  Packet.data(message.encodeBytes()).encode()
  ▼
DataChannelWrapper.sendBinary(bytes)
  │  (WebRTC data channel)
  ▼
Remote peer receives bytes
```

### Inbound Message

```
DataChannelWrapper receives bytes
  ▼
Connection._onChannelMessage(message)
  ▼
TransportLayer.receive(bytes)
  │  Packet.decode → P2PMessage.decodeBytes
  ▼
Connection._onTransportMessage(message)
  ├─► MessageController.add(message)  [Connection.onMessage stream]
  └─► MessageHandler.dispatch(message)
         │
         ├─► Typed handler (ping, pong, goodbye, ...)
         └─► P2PNode._buildConnection wires:
               conn.onData → EventBus.emit(MessageReceivedEvent)
               conn.onData → P2PNode.messageHandler.dispatch
```

### DHT RPC

```
P2PNode._dhtRpcTransport(targetPeerId, rpc)
  │  connection.send({...rpc, '_dhtRpc': true})
  ▼
Remote peer receives message
  │  P2PNode._handleDhtRpc(msg)
  └─► DHTNetwork.handleRpc(senderId, payload)
        │  returns response map
        └─► connection.send(response)
  ▼
Original caller receives response via Completer
```

---

## Lifecycle

```
[uninitialized]
      │ P2PNode()
      ▼
[constructed]
      │ node.initialize()
      ▼
[bootstrapping]  ← DHTNetwork.start()
                 ← WebRTCManager.initialize()
                 ← _bootstrap() (DHT self-lookup)
      │
      ▼
[online]         ← ready to connect/send/receive
      │
      │ node.stop()
      ▼
[stopping]       ← broadcast goodbye
                 ← channelManager.closeAll()
                 ← webrtcManager.dispose()
                 ← dhtNetwork.stop()
      │
      ▼
[offline]
```

---

## Design Principles

| Principle | Implementation |
|-----------|----------------|
| **Transport agnosticism** | `DHTNetwork` delegates RPC sending to an injectable `_sendRpc` function |
| **Signalling agnosticism** | `WebRTCManager.onSignalReady` callback lets `P2PNode` route signals over DHT |
| **Reactive streams** | `EventBus`, `StreamController.broadcast()`, RxDart for composable async pipelines |
| **Immutable configuration** | `P2PConfig` and sub-configs use `final` fields with sensible defaults |
| **Fail-fast validation** | `P2PConfig.validate()` throws `ConfigurationException` on bad values before startup |
| **Minimal dependencies** | Only `rxdart`, `pointycastle`, `uuid`, `crypto` — no platform channels required |

---

## Directory Structure

```
lib/
├── p2p_dart.dart              ← barrel export
└── src/
    ├── core/
    │   ├── channel_manager.dart
    │   ├── connection.dart
    │   ├── enums.dart
    │   ├── exceptions.dart
    │   ├── p2p_config.dart
    │   ├── p2p_node.dart
    │   └── peer_info.dart
    ├── dht/
    │   ├── bucket.dart
    │   ├── dht_config.dart
    │   ├── dht_network.dart
    │   ├── kademlia.dart
    │   └── routing_table.dart
    ├── events/
    │   ├── event_bus.dart
    │   └── events.dart
    ├── extensions/
    │   └── stream_extensions.dart
    ├── networking/
    │   ├── message.dart
    │   ├── message_handler.dart
    │   ├── packet.dart
    │   └── transport.dart
    ├── security/
    │   ├── auth_manager.dart
    │   └── crypto_utils.dart
    ├── utils/
    │   ├── buffer_manager.dart
    │   └── logger.dart
    └── webrtc/
        ├── data_channel_wrapper.dart
        ├── ice_configuration.dart
        ├── webrtc_config.dart
        └── webrtc_manager.dart

test/
├── integration/
│   └── p2p_node_test.dart
├── performance/
│   └── throughput_test.dart
└── unit/
    ├── buffer_test.dart
    ├── crypto_test.dart
    ├── event_bus_test.dart
    ├── kademlia_test.dart
    ├── peer_cache_test.dart
    └── routing_table_test.dart

example/
└── simple_chat.dart
```
