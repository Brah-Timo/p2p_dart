# WebRTC

This document explains how `p2p_dart` uses WebRTC for establishing direct, encrypted peer-to-peer data connections.

---

## Table of Contents

1. [WebRTC Primer](#webrtc-primer)
2. [Connection Establishment](#connection-establishment)
3. [Signalling Flow](#signalling-flow)
4. [ICE & NAT Traversal](#ice--nat-traversal)
5. [Data Channels](#data-channels)
6. [DataChannelWrapper](#datachannelwrapper)
7. [WebRTCManager API](#webrtcmanager-api)
8. [WebRTC Configuration](#webrtc-configuration)
9. [SDP Details](#sdp-details)
10. [Limitations & Notes](#limitations--notes)

---

## WebRTC Primer

WebRTC (Web Real-Time Communication) is a standard for direct, encrypted peer-to-peer communication. In `p2p_dart`, only the **data channel** feature is used (no audio/video).

Key concepts:

| Concept | Description |
|---------|-------------|
| **RTCPeerConnection** | The core WebRTC object managing the connection lifecycle |
| **SDP** (Session Description Protocol) | Describes media/data capabilities and network addresses |
| **ICE** (Interactive Connectivity Establishment) | The algorithm that discovers the best network path |
| **DTLS** | Encrypts all data channel traffic (mandatory, built into WebRTC) |
| **SCTP** | The transport protocol for data channels |
| **Signalling** | Out-of-band exchange of SDP and ICE candidates (not specified by WebRTC) |

---

## Connection Establishment

Establishing a WebRTC connection requires three steps:

```
OFFERER (Alice)                      ANSWERER (Bob)
     │                                     │
     │  1. createOffer()                   │
     │     Generate SDP offer              │
     │     Gather ICE candidates           │
     │                                     │
     │─── SDP offer + ICE candidates ─────►│
     │         (via signalling channel)    │
     │                                     │  2. handleOffer()
     │                                     │     Set remote SDP
     │                                     │     Generate SDP answer
     │                                     │     Gather ICE candidates
     │                                     │
     │◄── SDP answer + ICE candidates ─────│
     │                                     │
     │  3. handleAnswer()                  │
     │     Set remote SDP                  │
     │     Apply remote ICE candidates     │
     │                                     │
     │═══ DTLS handshake ═════════════════►│
     │◄══ DTLS handshake ══════════════════│
     │                                     │
     │═══════ Data Channel OPEN ═══════════│  ← PeerConnectedEvent
```

In `p2p_dart`, steps 1–3 are handled by `WebRTCManager`. The **signalling channel** is the DHT itself: SDP messages are relayed via the `P2PNode._forwardSignal` callback, which either:
- Sends the signal over an existing data channel (if one exists to an intermediary), or
- Stores it as `signal:<targetId>:<sourceId>` in the DHT for the target to pick up.

---

## Signalling Flow

```dart
// Initiating a connection from P2PNode:
await webrtcManager.createOffer(remotePeerInfo);

// This triggers:
//   webrtcManager.onSignalReady(targetPeerId, {type: 'offer', sdp: ..., candidates: [...]})
//   ↓
//   P2PNode._forwardSignal(targetPeerId, signal)
//   ↓
//   Stored in DHT or forwarded over existing connection

// When a signal arrives from the network:
await webrtcManager.handleSignalMessage(senderPeerId, signalMap);
```

### Signal Types

| Type | Sent By | Payload |
|------|---------|---------|
| `offer` | Offerer | `{type, sdp: {type, sdp}, candidates: [...]}` |
| `answer` | Answerer | `{type, sdp: {type, sdp}, candidates: [...]}` |
| `ice_candidate` | Either | `{type, candidate: {sdpMid, sdpMLineIndex, candidate}}` |
| `ice_complete` | Either | `{type}` — signals that gathering is done |
| `bye` | Either | `{type}` — graceful connection close |

---

## ICE & NAT Traversal

ICE (Interactive Connectivity Establishment) is the algorithm WebRTC uses to find a working network path through NATs and firewalls.

### Candidate Types

| Type | Description | Example |
|------|-------------|---------|
| **host** | Direct local address | `192.168.1.5:10000` |
| **srflx** | Server reflexive (STUN) — public IP behind NAT | `1.2.3.4:20000` |
| **relay** | TURN relay — when direct/STUN fail | `5.6.7.8:30000` |

`p2p_dart` gathers candidates via `WebRTCManager._gatherIceCandidates()`:

1. Always adds a **host** candidate (loopback for testing).
2. Queries each STUN server (takes first success) to discover the **srflx** candidate.
3. TURN relay candidates are added when `WebRTCConfig.turnServers` is configured.

### STUN Configuration

```dart
WebRTCConfig(
  stunServers: [
    StunServerConfig('stun.l.google.com'),   // port defaults to 3478
    StunServerConfig('stun1.l.google.com'),
    StunServerConfig('stun.example.com', port: 3478),
  ],
)
```

### TURN Configuration

```dart
WebRTCConfig(
  turnServers: [
    TurnServerConfig(
      host: 'turn.example.com',
      port: 3478,
      username: 'user',
      credential: 'pass',
    ),
  ],
)
```

TURN servers are used as a fallback when no direct path can be found (e.g., symmetric NATs).

---

## Data Channels

Once the WebRTC connection is established, a **data channel** is opened for application data. In `p2p_dart`, a single data channel labeled `"p2p-data"` (configurable) is used per peer connection.

### Properties

| Property | Default | Description |
|----------|---------|-------------|
| `label` | `"p2p-data"` | Channel identifier |
| `ordered` | `true` | Enforce message ordering |
| `maxRetransmits` | `null` | Unlimited retransmissions |
| `protocol` | `""` | Sub-protocol string |

Data channels are reliable and ordered by default (SCTP with retransmissions). For low-latency, unreliable delivery (e.g., game state), set `ordered: false` and `maxRetransmits: 0`.

---

## DataChannelWrapper

**File:** `lib/src/webrtc/data_channel_wrapper.dart`

Wraps a WebRTC data channel with a stream-based API.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `label` | `String` | Channel label |
| `remotePeerId` | `String` | Remote peer's ID |
| `isOpen` | `bool` | Whether the channel is open |
| `bytesSent` | `int` | Total bytes sent |
| `bytesReceived` | `int` | Total bytes received |
| `onMessage` | `Stream<DataChannelMessage>` | Incoming messages |
| `onStateChange` | `Stream<DataChannelState>` | State transitions |

### Methods

```dart
// Send raw bytes.
void sendBinary(Uint8List bytes)

// Send a JSON map (serialised internally).
void sendJson(Map<String, dynamic> map)

// Close the channel.
Future<void> close()

// Mark as open (used by WebRTCManager after handshake).
void markOpen()
```

### DataChannelMessage

```dart
class DataChannelMessage {
  final bool isBinary;
  final Uint8List? binary;
  final String? text;
}
```

---

## WebRTCManager API

**File:** `lib/src/webrtc/webrtc_manager.dart`

```dart
// Lifecycle.
await webrtcManager.initialize();
await webrtcManager.dispose();

// Initiate a connection.
final channel = await webrtcManager.createOffer(peerInfo);

// Handle incoming signals.
await webrtcManager.handleSignalMessage(senderPeerId, signalMap);

// Channel access.
final channel = webrtcManager.getChannel(peerId);
final isOpen = webrtcManager.hasActiveChannel(peerId);
final peers = webrtcManager.connectedPeers; // Iterable<String>

// Close a specific channel.
await webrtcManager.closeChannel(peerId);

// Signalling callback (set by P2PNode).
webrtcManager.onSignalReady = (targetPeerId, signal) async {
  // Forward the signal to the target peer via DHT or existing connection.
};
```

---

## WebRTC Configuration

```dart
P2PConfig(
  webrtc: WebRTCConfig(
    // STUN servers for NAT traversal.
    stunServers: [
      StunServerConfig('stun.l.google.com'),
      StunServerConfig('stun1.l.google.com'),
    ],

    // TURN relay servers (fallback).
    turnServers: [
      TurnServerConfig(
        host: 'turn.example.com',
        username: 'user',
        credential: 'secret',
      ),
    ],

    // Max wait for WebRTC handshake (default: 30 s).
    connectionTimeout: Duration(seconds: 30),

    // Max wait for ICE gathering (default: 5 s).
    iceGatheringTimeout: Duration(seconds: 5),

    // Max ICE candidates to collect (default: 50).
    maxIceCandidates: 50,

    // Default data channel settings.
    defaultChannel: DataChannelConfig(
      label: 'p2p-data',
      ordered: true,
    ),
  ),
)
```

---

## SDP Details

The SDP (Session Description Protocol) offer/answer generated by `p2p_dart` follows the standard WebRTC format:

```
v=0
o=- <sessionId> 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE data
m=application 9 UDP/DTLS/SCTP webrtc-datachannel
c=IN IP4 0.0.0.0
a=ice-ufrag:<4 random chars>
a=ice-pwd:<22 random chars>
a=ice-options:trickle
a=fingerprint:sha-256 <64 hex bytes separated by :>
a=setup:actpass   (offer) | active (answer)
a=mid:data
a=sctp-port:5000
a=max-message-size:262144
```

In production, the `RTCPeerConnection` API (via `flutter_webrtc` or similar) generates real SDP with actual network addresses. `p2p_dart` uses **synthetic SDP** for testing purposes.

---

## Limitations & Notes

1. **Real WebRTC integration** — `p2p_dart` currently uses synthetic SDP/ICE for unit testability. In a real application, wire in a WebRTC native package (e.g., `flutter_webrtc`, `dart_webrtc`) by replacing `_generateSyntheticSdp` and `_gatherIceCandidates` in `WebRTCManager`.

2. **Offer-answer interlock** — only one pending offer per peer is supported. Simultaneous connections from both sides (glare) are not handled; the answerer's side wins.

3. **ICE restart** — not implemented. If ICE fails (e.g., network change), the connection closes and must be re-established.

4. **Data channel multiplexing** — currently one data channel per peer. Multiple named channels per peer can be added by extending `DataChannelWrapper`.

5. **Max message size** — the default `max-message-size` is 262144 bytes (256 KiB). Messages larger than `PerformanceConfig.maxMessageSize` (default 64 KiB) should be chunked via `Chunker.split`.
