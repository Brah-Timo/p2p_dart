# Configuration Reference

Complete reference for all configuration classes in `p2p_dart`.

---

## Table of Contents

1. [P2PConfig](#p2pconfig)
2. [DHTConfig](#dhtconfig)
3. [WebRTCConfig](#webrtcconfig)
4. [SecurityConfig](#securityconfig)
5. [PerformanceConfig](#performanceconfig)
6. [LoggingConfig](#loggingconfig)
7. [StunServerConfig](#stunserverconfig)
8. [TurnServerConfig](#turnserverconfig)
9. [DataChannelConfig](#datachannelconfig)
10. [Example Configurations](#example-configurations)

---

## P2PConfig

**File:** `lib/src/core/p2p_config.dart`

The top-level configuration object passed to `P2PNode`.

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

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `dht` | `DHTConfig?` | `DHTConfig()` | DHT settings; if `bootstrapPeers` is also set, `dht` takes precedence |
| `webrtc` | `WebRTCConfig?` | `WebRTCConfig()` | WebRTC settings |
| `security` | `SecurityConfig?` | `SecurityConfig()` | Security settings |
| `performance` | `PerformanceConfig?` | `PerformanceConfig()` | Performance tuning |
| `logging` | `LoggingConfig?` | `LoggingConfig()` | Logging settings |
| `peerId` | `String?` | `null` | Fixed peer ID (must be exactly 40 hex characters). Randomly generated if `null`. |
| `displayName` | `String?` | `null` | Optional human-readable name advertised to peers |
| `protocolVersion` | `String` | `'1.0.0'` | Application protocol version. Incompatible versions may refuse connections. |
| `bootstrapPeers` | `List<String>?` | `null` | Shorthand to set `dht.bootstrapPeers`. Ignored if `dht` is explicitly provided. |

### Validation

Call `config.validate()` to check all sub-configs before passing to `P2PNode`. `P2PNode` calls this automatically in its constructor.

---

## DHTConfig

**File:** `lib/src/dht/dht_config.dart`

Controls the Kademlia DHT behaviour.

```dart
const DHTConfig({
  List<String> bootstrapPeers = const [],
  int bucketSize = 20,
  int alpha = 3,
  int replicationFactor = 3,
  int maxLookupHops = 20,
  Duration bucketRefreshInterval = const Duration(hours: 1),
  Duration republishInterval = const Duration(hours: 1),
  Duration valueTtl = const Duration(hours: 24),
  Duration rpcTimeout = const Duration(seconds: 10),
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `bootstrapPeers` | `List<String>` | `[]` | 40-char hex peer IDs of known seed nodes to connect to on startup |
| `bucketSize` | `int` | `20` | Maximum peers per k-bucket (the Kademlia *k* parameter) |
| `alpha` | `int` | `3` | Number of parallel RPCs during iterative lookups |
| `replicationFactor` | `int` | `3` | Number of nearest peers to replicate stored values to |
| `maxLookupHops` | `int` | `20` | Maximum rounds per iterative lookup before giving up |
| `bucketRefreshInterval` | `Duration` | `1 hour` | How often to refresh stale routing buckets |
| `republishInterval` | `Duration` | `1 hour` | How often to re-store locally owned records |
| `valueTtl` | `Duration` | `24 hours` | Default time-to-live for DHT records |
| `rpcTimeout` | `Duration` | `10 sec` | Timeout for a single outbound DHT RPC |

**Tuning tips:**
- Reduce `alpha` on low-bandwidth networks.
- Increase `bucketSize` for larger networks (50–100 for thousands of nodes).
- Shorten `valueTtl` for frequently changing data; lengthen for static resources.

---

## WebRTCConfig

**File:** `lib/src/webrtc/webrtc_config.dart`

Controls WebRTC peer connection and data channel behaviour.

```dart
WebRTCConfig({
  List<StunServerConfig> stunServers = const [StunServerConfig('stun.l.google.com')],
  List<TurnServerConfig> turnServers = const [],
  Duration connectionTimeout = const Duration(seconds: 30),
  Duration iceGatheringTimeout = const Duration(seconds: 5),
  DataChannelConfig defaultChannel = const DataChannelConfig(),
  int maxIceCandidates = 50,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `stunServers` | `List<StunServerConfig>` | `[stun.l.google.com:3478]` | STUN servers used to discover the public IP address |
| `turnServers` | `List<TurnServerConfig>` | `[]` | TURN relay servers used when no direct path exists |
| `connectionTimeout` | `Duration` | `30 sec` | Max time to complete the full WebRTC handshake |
| `iceGatheringTimeout` | `Duration` | `5 sec` | Max time to wait for ICE candidate gathering |
| `defaultChannel` | `DataChannelConfig` | `DataChannelConfig()` | Configuration for the default data channel |
| `maxIceCandidates` | `int` | `50` | Maximum number of ICE candidates to collect |

---

## SecurityConfig

**File:** `lib/src/core/p2p_config.dart`

Controls encryption and authentication behaviour.

```dart
const SecurityConfig({
  bool enforceEncryption = true,
  bool requireAuthentication = false,
  Duration authTimeout = const Duration(seconds: 15),
  List<String> trustedPeers = const [],
  int maxAuthFailures = 5,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `enforceEncryption` | `bool` | `true` | Terminate connections that fail DTLS handshake |
| `requireAuthentication` | `bool` | `false` | Require HMAC challenge-response from all peers |
| `authTimeout` | `Duration` | `15 sec` | Maximum time for an auth handshake to complete |
| `trustedPeers` | `List<String>` | `[]` | If non-empty and `requireAuthentication` is true, only these peer IDs may connect |
| `maxAuthFailures` | `int` | `5` | Number of failed auth attempts before a peer is banned |

---

## PerformanceConfig

**File:** `lib/src/core/p2p_config.dart`

Controls connection limits, buffering, and heartbeat behaviour.

```dart
const PerformanceConfig({
  int maxConnections = 100,
  int sendBufferSize = 1000,
  int maxMessageSize = 65536,
  Duration heartbeatInterval = const Duration(seconds: 30),
  bool enableCompression = false,
  int compressionThreshold = 512,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `maxConnections` | `int` | `100` | Maximum simultaneous open peer connections |
| `sendBufferSize` | `int` | `1000` | Maximum messages queued per connection before throwing `TransportException` |
| `maxMessageSize` | `int` | `65536` (64 KiB) | Maximum single message size; larger payloads should be chunked |
| `heartbeatInterval` | `Duration` | `30 sec` | Interval between heartbeat pings |
| `enableCompression` | `bool` | `false` | Enable GZIP compression on message payloads |
| `compressionThreshold` | `int` | `512` | Minimum payload size (bytes) before compression is applied |

**Notes:**
- `maxConnections` applies to the `ChannelManager` registry. Excess connections are rejected.
- `sendBufferSize` is per-connection. Set higher for bursty workloads.
- Compression adds ~1–2 ms CPU overhead per message; only worthwhile for payloads > 1 KiB on slow links.

---

## LoggingConfig

**File:** `lib/src/core/p2p_config.dart`

Controls log verbosity and destination.

```dart
const LoggingConfig({
  bool verbose = false,
  bool logSensitiveData = false,
  void Function(String level, String component, String message)? onLog,
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `verbose` | `bool` | `false` | Enable DEBUG-level messages |
| `logSensitiveData` | `bool` | `false` | Allow cryptographic bytes / keys in log output |
| `onLog` | `Function?` | `null` | Custom log callback. If `null`, logs go to `dart:developer` |

### Custom Log Sink

```dart
LoggingConfig(
  verbose: true,
  onLog: (level, component, message) {
    // level: 'DEBUG', 'INFO', 'WARNING', 'ERROR'
    // component: 'P2PNode', 'DHT', 'Transport', etc.
    print('[$level][$component] $message');
  },
)
```

---

## StunServerConfig

**File:** `lib/src/webrtc/ice_configuration.dart`

```dart
const StunServerConfig(String host, {int port = 3478})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `host` | `String` | — | STUN server hostname or IP |
| `port` | `int` | `3478` | STUN server port |

### Public STUN Servers

```dart
const knownStunServers = [
  StunServerConfig('stun.l.google.com'),      // Google (3478)
  StunServerConfig('stun1.l.google.com'),
  StunServerConfig('stun.cloudflare.com'),    // Cloudflare
  StunServerConfig('stun.stunprotocol.org'),
];
```

---

## TurnServerConfig

**File:** `lib/src/webrtc/ice_configuration.dart`

```dart
const TurnServerConfig({
  required String host,
  int port = 3478,
  required String username,
  required String credential,
  String transport = 'udp',  // 'udp' or 'tcp'
})
```

TURN servers relay traffic when direct peer-to-peer is impossible (e.g., symmetric NATs, strict corporate firewalls).

---

## DataChannelConfig

**File:** `lib/src/webrtc/webrtc_config.dart`

```dart
const DataChannelConfig({
  String label = 'p2p-data',
  bool ordered = true,
  int? maxRetransmits,
  int? maxPacketLifeTime,
  String protocol = '',
})
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `label` | `String` | `'p2p-data'` | Channel identifier string |
| `ordered` | `bool` | `true` | Enforce delivery order |
| `maxRetransmits` | `int?` | `null` | Max retransmissions before dropping; `null` = unlimited |
| `maxPacketLifeTime` | `int?` | `null` | Max ms to attempt delivery |
| `protocol` | `String` | `''` | Sub-protocol name |

---

## Example Configurations

### Minimal (isolated node, no bootstrap)

```dart
final node = P2PNode(config: P2PConfig());
```

### Bootstrap node with defaults

```dart
final node = P2PNode(
  config: P2PConfig(
    bootstrapPeers: ['aabbccdd...40chars...'],
  ),
);
```

### Production-grade configuration

```dart
final node = P2PNode(
  config: P2PConfig(
    peerId: null,                    // auto-generate
    displayName: 'production-node',
    protocolVersion: '2.0.0',

    dht: DHTConfig(
      bootstrapPeers: ['seed1...', 'seed2...'],
      bucketSize: 20,
      alpha: 3,
      replicationFactor: 5,
      valueTtl: Duration(hours: 48),
      rpcTimeout: Duration(seconds: 15),
    ),

    webrtc: WebRTCConfig(
      stunServers: [
        StunServerConfig('stun.l.google.com'),
        StunServerConfig('stun.cloudflare.com'),
      ],
      turnServers: [
        TurnServerConfig(
          host: 'turn.myapp.com',
          username: 'p2p',
          credential: 'secret',
        ),
      ],
      connectionTimeout: Duration(seconds: 45),
    ),

    security: SecurityConfig(
      enforceEncryption: true,
      requireAuthentication: true,
      maxAuthFailures: 3,
    ),

    performance: PerformanceConfig(
      maxConnections: 500,
      sendBufferSize: 2000,
      maxMessageSize: 131072,         // 128 KiB
      heartbeatInterval: Duration(seconds: 60),
      enableCompression: true,
      compressionThreshold: 1024,
    ),

    logging: LoggingConfig(
      verbose: false,
      logSensitiveData: false,
      onLog: (level, component, msg) => myLogger.log(level, component, msg),
    ),
  ),
);
```

### Low-latency gaming configuration

```dart
P2PConfig(
  webrtc: WebRTCConfig(
    defaultChannel: DataChannelConfig(
      label: 'game',
      ordered: false,         // no ordering
      maxRetransmits: 0,      // drop lost packets (unreliable)
    ),
  ),
  performance: PerformanceConfig(
    heartbeatInterval: Duration(seconds: 10),
    sendBufferSize: 200,
  ),
)
```

### Local testing (no STUN, no bootstrap)

```dart
P2PConfig(
  webrtc: WebRTCConfig(
    stunServers: [],          // no STUN
  ),
  security: SecurityConfig(
    enforceEncryption: false, // disable for localhost testing
    requireAuthentication: false,
  ),
  logging: LoggingConfig(verbose: true),
)
```
