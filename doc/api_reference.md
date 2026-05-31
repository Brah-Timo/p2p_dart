# API Reference

Complete reference for all public classes, methods, and types in `p2p_dart`.

---

## Table of Contents

- [P2PNode](#p2pnode)
- [P2PConfig](#p2pconfig)
- [DHTConfig](#dhtconfig)
- [WebRTCConfig](#webrtcconfig)
- [SecurityConfig](#securityconfig)
- [PerformanceConfig](#performanceconfig)
- [LoggingConfig](#loggingconfig)
- [Connection](#connection)
- [P2PMessage](#p2pmessage)
- [PeerInfo](#peerinfo)
- [EventBus & Events](#eventbus--events)
- [Enums](#enums)
- [Exceptions](#exceptions)
- [Stream Extensions](#stream-extensions)

---

## P2PNode

**File:** `lib/src/core/p2p_node.dart`

The central peer-to-peer node. Acts as both client and server.

### Constructor

```dart
P2PNode({P2PConfig? config})
```

Creates a node. Does **not** start it — call `initialize()`.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `config` | `P2PConfig` | The configuration this node was created with |
| `peerId` | `String` | 40-char hex Kademlia peer ID (set after `initialize()`) |
| `status` | `NodeStatus` | Current operational status |
| `isOnline` | `bool` | `true` when `status == NodeStatus.online` |
| `eventBus` | `EventBus` | Application-level typed event bus |
| `messageHandler` | `MessageHandler` | Global inbound message middleware pipeline |
| `dhtNetwork` | `DHTNetwork` | The DHT subsystem |
| `webrtcManager` | `WebRTCManager` | The WebRTC subsystem |
| `channelManager` | `ChannelManager` | The connection registry |
| `knownPeers` | `List<String>` | Peer IDs known to the local routing table |
| `connectedPeerIds` | `Iterable<String>` | Peer IDs with active connections |
| `connectionCount` | `int` | Number of active connections |
| `onStatusChange` | `Stream<NodeStatus>` | Stream of status transitions |

### Methods

#### Lifecycle

```dart
Future<void> initialize()
```
Starts the DHT, WebRTC, and bootstraps into the network.  
Throws `InitializationException` if already running.

```dart
Future<void> stop()
```
Gracefully shuts down. Broadcasts a goodbye, closes all connections, stops subsystems.

#### Connectivity

```dart
Future<Connection> connect(String remotePeerId)
```
Connects to a peer. Returns an existing connection if healthy.  
Throws `SelfConnectionException`, `PeerNotFoundException`, `ConnectionTimeoutException`.

```dart
bool isConnectedTo(String remotePeerId)
```
Returns `true` if there is an active connection to `remotePeerId`.

```dart
Connection? connectionTo(String remotePeerId)
```
Returns the `Connection` object, or `null` if not connected.

```dart
Future<void> disconnect(String remotePeerId)
```
Closes the connection to `remotePeerId`.

#### Messaging

```dart
Future<void> send(String targetPeerId, Map<String, dynamic> data)
```
Sends a JSON map to one peer. Throws `ConnectionClosedException` if not connected.

```dart
Future<void> sendText(String targetPeerId, String text)
```
Sends a plain string wrapped in `{'text': text}`.

```dart
Future<void> broadcast(Map<String, dynamic> data)
```
Sends `data` to all currently connected peers.

```dart
Future<void> sendToMany(Iterable<String> peerIds, Map<String, dynamic> data)
```
Sends to only the specified subset of peers.

#### DHT

```dart
Future<void> dhtPut(String key, String value)
```
Stores `value` under `key` in the distributed hash table.

```dart
Future<String?> dhtGet(String key)
```
Retrieves the value for `key`. Returns `null` if not found.

---

## P2PConfig

**File:** `lib/src/core/p2p_config.dart`

Master configuration bundle consumed by `P2PNode`.

### Constructor

```dart
P2PConfig({
  DHTConfig? dht,
  WebRTCConfig? webrtc,
  SecurityConfig? security,
  PerformanceConfig? performance,
  LoggingConfig? logging,
  String? peerId,
  String? displayName,
  String protocolVersion = '1.0.0',
  List<String>? bootstrapPeers,
})
```

`bootstrapPeers` is a convenience shorthand that creates a `DHTConfig(bootstrapPeers: ...)` automatically.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `dht` | `DHTConfig` | `DHTConfig()` | DHT settings |
| `webrtc` | `WebRTCConfig` | `WebRTCConfig()` | WebRTC/ICE settings |
| `security` | `SecurityConfig` | `SecurityConfig()` | Security settings |
| `performance` | `PerformanceConfig` | `PerformanceConfig()` | Performance settings |
| `logging` | `LoggingConfig` | `LoggingConfig()` | Logging settings |
| `peerId` | `String?` | `null` | Fixed peer ID (40 hex chars) |
| `displayName` | `String?` | `null` | Human-readable name |
| `protocolVersion` | `String` | `'1.0.0'` | Protocol version string |

### Methods

```dart
void validate()
```
Validates all sub-configs. Throws `ConfigurationException` on invalid values.

---

## DHTConfig

**File:** `lib/src/dht/dht_config.dart`

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `bootstrapPeers` | `List<String>` | `[]` | Initial peers for bootstrapping |
| `bucketSize` | `int` | `20` | Kademlia k parameter |
| `alpha` | `int` | `3` | Parallelism for iterative lookups |
| `replicationFactor` | `int` | `3` | Number of closest peers to replicate to |
| `maxLookupHops` | `int` | `20` | Maximum hops before lookup gives up |
| `bucketRefreshInterval` | `Duration` | `1 hour` | How often to refresh stale buckets |
| `republishInterval` | `Duration` | `1 hour` | How often to republish stored records |
| `valueTtl` | `Duration` | `24 hours` | Default TTL for stored values |
| `rpcTimeout` | `Duration` | `10 seconds` | Timeout for individual DHT RPCs |

---

## WebRTCConfig

**File:** `lib/src/webrtc/webrtc_config.dart`

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `stunServers` | `List<StunServerConfig>` | `[stun.l.google.com]` | STUN servers for NAT traversal |
| `turnServers` | `List<TurnServerConfig>` | `[]` | TURN relay servers |
| `connectionTimeout` | `Duration` | `30 seconds` | Max time to complete a WebRTC handshake |
| `iceGatheringTimeout` | `Duration` | `5 seconds` | Max time for ICE gathering |
| `defaultChannel` | `DataChannelConfig` | `DataChannelConfig()` | Default data channel settings |
| `maxIceCandidates` | `int` | `50` | Max ICE candidates to gather |

---

## SecurityConfig

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `enforceEncryption` | `bool` | `true` | Terminate connections failing DTLS |
| `requireAuthentication` | `bool` | `false` | Require HMAC challenge-response |
| `authTimeout` | `Duration` | `15 seconds` | Auth handshake timeout |
| `trustedPeers` | `List<String>` | `[]` | Whitelist (when `requireAuthentication: true`) |
| `maxAuthFailures` | `int` | `5` | Failures before banning a peer |

---

## PerformanceConfig

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `maxConnections` | `int` | `100` | Maximum simultaneous open connections |
| `sendBufferSize` | `int` | `1000` | Max messages buffered per connection |
| `maxMessageSize` | `int` | `65536` | Max bytes per message (larger is chunked) |
| `heartbeatInterval` | `Duration` | `30 seconds` | Interval between heartbeat pings |
| `enableCompression` | `bool` | `false` | Enable GZIP payload compression |
| `compressionThreshold` | `int` | `512` | Minimum bytes before compressing |

---

## LoggingConfig

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `verbose` | `bool` | `false` | Enable debug-level messages |
| `logSensitiveData` | `bool` | `false` | Allow crypto bytes in logs |
| `onLog` | `Function?` | `null` | Custom log sink (level, component, message) |

---

## Connection

**File:** `lib/src/core/connection.dart`

Represents an active connection to one remote peer.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `localPeerId` | `String` | Local node's peer ID |
| `remotePeerId` | `String` | Remote peer's ID |
| `remotePeerInfo` | `PeerInfo` | Remote peer metadata |
| `state` | `ConnectionState` | Current connection state |
| `isConnected` | `bool` | `state == connected` |
| `onStateChange` | `Stream<ConnectionState>` | State transition events |
| `onMessage` | `Stream<P2PMessage>` | All inbound messages |
| `onData` | `Stream<P2PMessage>` | DATA messages only |

### Methods

```dart
Future<void> send(Map<String, dynamic> data)
Future<void> sendText(String text)
Future<void> sendBinary(Uint8List bytes)
Future<void> close()
ConnectionStats stats()
void on(MessageType type, TypedMessageHandler handler)
void use(MessageMiddleware middleware)
```

---

## P2PMessage

**File:** `lib/src/networking/message.dart`

The core protocol message exchanged between peers.

### Constructor

```dart
P2PMessage({
  required MessageType type,
  required String senderId,
  String? correlationId,
  Map<String, dynamic>? payload,
  Uint8List? binaryPayload,
  String protocolVersion = '1.0.0',
  int? timestamp,
})
```

### Factory Constructors

```dart
P2PMessage.data(String senderId, Map<String, dynamic> data)
P2PMessage.ping(String senderId)
P2PMessage.pong(String senderId, String replyTo)
P2PMessage.ack(String senderId, String messageId)
P2PMessage.goodbye(String senderId)
P2PMessage.error(String senderId, String errorMessage)
P2PMessage.decode(String raw)
P2PMessage.decodeBytes(Uint8List bytes)
P2PMessage.fromJson(Map<String, dynamic> json)
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `type` | `MessageType` | Message classification |
| `correlationId` | `String` | Request/response matching token |
| `senderId` | `String` | Originating peer ID |
| `timestamp` | `int` | Unix ms creation timestamp |
| `payload` | `Map<String, dynamic>?` | JSON payload |
| `binaryPayload` | `Uint8List?` | Raw binary payload |
| `isControl` | `bool` | True for ping/pong/ack/goodbye/error |
| `age` | `Duration` | Time since creation |

---

## PeerInfo

**File:** `lib/src/core/peer_info.dart`

A value object describing a known peer.

```dart
PeerInfo({
  required String peerId,
  List<String> addresses = const [],
  String? displayName,
  Map<String, dynamic> metadata = const {},
})
```

| Property | Type | Description |
|----------|------|-------------|
| `peerId` | `String` | 40-char hex Kademlia ID |
| `addresses` | `List<String>` | Known transport addresses |
| `displayName` | `String?` | Optional human-readable name |
| `metadata` | `Map<String, dynamic>` | Application-defined metadata |
| `lastSeen` | `DateTime` | Last contact timestamp |

---

## EventBus & Events

**File:** `lib/src/events/event_bus.dart`, `lib/src/events/events.dart`

```dart
// Subscribe.
final cancel = eventBus.on<MyEvent>((event) { ... });

// Emit.
eventBus.emit(MyEvent(...));

// Unsubscribe.
cancel();
```

### Built-in Events

| Event | Fields | When |
|-------|--------|------|
| `NodeStartedEvent` | `peerId` | After `initialize()` completes |
| `NodeStoppedEvent` | `peerId` | After `stop()` completes |
| `PeerConnectedEvent` | `peerId, channel` | WebRTC channel established |
| `PeerDisconnectedEvent` | `peerId, reason` | WebRTC channel closed |
| `PeerLeftEvent` | `peerId, reason` | Connection closed (higher-level) |
| `MessageReceivedEvent` | `senderId, data, rawMessage` | Inbound DATA message |
| `DHTBootstrappedEvent` | `localId` | DHT bootstrap complete |
| `DHTValueStoredEvent` | `key, value` | Value stored in DHT |

---

## Enums

**File:** `lib/src/core/enums.dart`

### `MessageType`

```dart
enum MessageType {
  data, ping, pong, ack, goodbye, error,
  dhtPing, dhtPong, dhtFindNode, dhtFindValue, dhtStore,
}
```

### `ConnectionState`

```dart
enum ConnectionState { idle, connecting, connected, disconnected, closed }
```

### `NodeStatus`

```dart
enum NodeStatus { uninitialized, bootstrapping, online, stopping, offline }
```

### `DataChannelState`

```dart
enum DataChannelState { connecting, open, closing, closed }
```

### `DiscoveryMethod`

```dart
enum DiscoveryMethod { dhtRoutingTable, dhtLookup, direct, mdns, bootstrap }
```

---

## Exceptions

**File:** `lib/src/core/exceptions.dart`

| Exception | Description |
|-----------|-------------|
| `P2PException` | Root exception type |
| `InitializationException` | Node init failed or wrong state |
| `ConnectionException` | Connection attempt failed |
| `ConnectionClosedException` | Send on closed connection |
| `SelfConnectionException` | Attempted to connect to self |
| `ConnectionTimeoutException` | Handshake timed out |
| `PeerNotFoundException` | Peer not found in DHT |
| `DHTException` | DHT operation failed |
| `WebRTCException` | WebRTC-level failure |
| `SDPException` | SDP negotiation failed |
| `ICEException` | ICE gathering/check failed |
| `CryptoException` | Cryptographic operation failed |
| `AuthenticationException` | Peer auth failed |
| `DataChannelException` | Data channel error |
| `TransportException` | Network send/receive failed |
| `SerializationException` | Message (de)serialisation failed |
| `ConfigurationException` | Invalid configuration values |

---

## Stream Extensions

**File:** `lib/src/extensions/stream_extensions.dart`

```dart
extension P2PStreamExtensions<T> on Stream<T> {
  // Convert to broadcast.
  Stream<T> asBroadcast()

  // Get first event of type S.
  Future<S> firstOfType<S>()

  // Batch events into lists of [size].
  Stream<List<T>> batch(int size)

  // Debounce: only emit after [duration] of silence.
  Stream<T> debounce(Duration duration)

  // Throttle: at most one event per [interval].
  Stream<T> throttle(Duration interval)

  // Emit consecutive (previous, current) pairs.
  Stream<(T, T)> pairwise()
}
```
