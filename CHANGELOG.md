# Changelog

All notable changes to **p2p_dart** are documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/).

---

## [1.0.0] — 2026-05-31

### 🎉 Initial Release

#### Core
- `P2PNode` — main entry point with `initialize()`, `stop()`, `connect()`,
  `send()`, `broadcast()`, `sendToMany()`, `disconnect()`.
- `P2PConfig` — unified configuration with `DHTConfig`, `WebRTCConfig`,
  `SecurityConfig`, `PerformanceConfig`, `LoggingConfig`.
- `Connection` — individual peer connection with heartbeat keep-alive,
  `onMessage` / `onData` streams, and `ConnectionStats`.
- `ChannelManager` — LRU connection registry with broadcast helpers.
- `PeerInfo` — immutable value object with ICE candidates, addresses, public key.

#### DHT
- `DHTNetwork` — full Kademlia implementation with FIND_NODE, FIND_VALUE,
  STORE, PING RPCs.
- `RoutingTable` — dynamic k-bucket split on demand.
- `KBucket` — LRU eviction, replacement cache, failure tracking.
- `Kademlia` — pure-function XOR-metric utilities, ID generation, sorting.
- `DHTConfig` — fully parameterised (k, α, replication, TTL, timeouts).

#### WebRTC
- `WebRTCManager` — offer/answer SDP exchange, ICE gathering, signal routing.
- `WebRTCConfig` — STUN/TURN server lists, ICE timeouts, data-channel options.
- `IceConfiguration` — resolved ICE server map for `RTCPeerConnection`.
- `IceCandidatePool` — priority-ranked candidate collection.
- `StunClient` — pure-Dart RFC 5389 STUN Binding Request implementation.
- `DataChannelWrapper` — transport-agnostic data channel with stats.

#### Networking
- `P2PMessage` — typed protocol messages with correlation IDs and timestamps.
- `MessageHandler` — middleware chain + per-type handler registry.
- `TransportLayer` — send queue, optional ACK tracking, retransmission.
- `Packet` / `PacketHeader` — 8-byte framing with flag bits.
- `FragmentManager` — transparent MTU splitting and reassembly.

#### Security
- `DHKeyExchange` — ECDH over NIST P-256 with HKDF-SHA256 session key derivation.
- `MessageEncryptor` — AES-256-GCM encrypt/decrypt with HMAC-SHA256 authentication.
- `DtlsHandler` — DTLS certificate fingerprint generation and verification.
- `CryptoUtils` — SHA-256, HMAC-SHA256, AES-GCM, PBKDF2, constant-time compare.
- `AuthManager` — HMAC challenge-response peer authentication.

#### Discovery
- `PeerDiscovery` — multi-strategy orchestrator (cache → mDNS → DHT).
- `LocalNetworkDiscovery` — local subnet probe / mDNS stub.
- `PeerCache` — capacity-bounded LRU cache with TTL expiry.

#### Events
- `EventBus` — type-safe, synchronous pub/sub with `on()`, `once()`, `next()`,
  `stream()`, `cancel()`.
- 14 event types: `NodeStartedEvent`, `PeerConnectedEvent`,
  `MessageReceivedEvent`, `DHTBootstrappedEvent`, and more.

#### Utils & Extensions
- `P2PLogger` — levelled structured logger with custom sink support.
- `GrowingBuffer` — dynamically growing byte buffer.
- `Chunker` — split / join utilities for large payloads.
- `RingBuffer<T>` — fixed-capacity circular queue.
- `AsyncUtils` — `retry()`, `debounce()`, `throttle()`, `CompleterPool`.
- Stream extensions: `batch()`, `debounce()`, `throttle()`, `pairwise()`.
- Future extensions: `orNullOnTimeout()`, `orElse()`, `tap()`, `timed()`.
- String / `Uint8List` extensions.

#### Examples
- `simple_chat.dart` — full CLI P2P chat with history.
- `file_sharing.dart` — chunked binary file transfer with progress.
- `multiplayer_game.dart` — real-time position sync (20 Hz game loop).
- `decentralized_storage.dart` — DHT CRUD + content-addressable storage.

#### Tests
- Unit tests for Kademlia, RoutingTable, EventBus, PeerCache, buffers,
  CryptoUtils, and KeyExchange.
- Integration tests for `P2PNode` lifecycle and DHT operations.
- Performance benchmarks for Chunker, AES-GCM, RoutingTable, and EventBus.

---

## [Unreleased]

### Planned
- Flutter WebRTC integration (`flutter_webrtc` / `dart_webrtc` backend).
- Real multicast mDNS peer discovery via `multicast_dns`.
- Noise Protocol XX handshake.
- QUIC transport.
- GitHub Actions CI.
- pub.dev publication.
