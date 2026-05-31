# Distributed Hash Table (DHT)

`p2p_dart` uses a **Kademlia**-based Distributed Hash Table for decentralised peer discovery and key-value storage.

---

## Table of Contents

1. [What is Kademlia?](#what-is-kademlia)
2. [Peer IDs](#peer-ids)
3. [XOR Distance Metric](#xor-distance-metric)
4. [Routing Table & K-Buckets](#routing-table--k-buckets)
5. [Iterative Lookup](#iterative-lookup)
6. [Key-Value Storage](#key-value-storage)
7. [Bootstrap Process](#bootstrap-process)
8. [RPCs](#rpcs)
9. [Background Tasks](#background-tasks)
10. [DHT Configuration Reference](#dht-configuration-reference)
11. [Key Classes](#key-classes)

---

## What is Kademlia?

Kademlia is a peer-to-peer DHT protocol with the following guarantees:

- **Decentralisation** — no central directory; all peers are equal.
- **Efficient lookup** — finding any peer or value requires at most `O(log n)` network hops.
- **Fault tolerance** — replicated storage and redundant routing paths ensure resilience.
- **Self-organising** — nodes maintain their routing tables incrementally as they receive messages.

`p2p_dart`'s implementation (`DHTNetwork`, `RoutingTable`, `Kademlia`) is **transport-agnostic**: it does not open sockets directly. Instead, it delegates RPC sending to a function injected by `P2PNode`, meaning RPCs travel over the same WebRTC data channels used for application data.

---

## Peer IDs

Every node and every stored key is identified by a **160-bit Kademlia ID**, represented as a 40-character lowercase hex string.

```dart
// Generate a random 160-bit ID.
final id = Kademlia.generateId();  // e.g. "a3f8c1b2..."

// Derive from a public key (SHA-1).
final id = Kademlia.idFromPublicKey(publicKeyBytes);

// Derive from a string (SHA-1).
final key = Kademlia.keyFromString('my-resource');

// Validate.
final ok = Kademlia.isValidId(id);  // must be exactly 40 hex chars
```

---

## XOR Distance Metric

Two nodes' IDs are compared using **bitwise XOR**. The result is a 160-bit integer interpreted as the "distance" between them.

```dart
// Returns a BigInt.
final d = Kademlia.distance('aabbcc...', '112233...');

// Sort peers by distance from a target ID.
final sorted = Kademlia.sortByDistance(
  targetId: target,
  peers: peerList,
  getId: (p) => p.peerId,
);

// Get the k closest peers.
final closest = Kademlia.closestN(
  targetId: target,
  candidates: peerList,
  getId: (p) => p.peerId,
  count: 20,
);
```

The XOR metric has a key property: for any three IDs `a, b, c`, if `distance(a, b) < distance(a, c)`, then `b` is "closer" to `a` than `c` is in the ID space.

---

## Routing Table & K-Buckets

Each node maintains a `RoutingTable` consisting of up to **160 k-buckets**, one per bit of the ID space.

### K-Bucket

A `KBucket` holds up to **k** (default 20) entries, each being a `PeerInfo`:

- Entries are ordered **least-recently-seen (LRS) first** and **most-recently-seen (MRS) last**.
- When a bucket is full, new peers go into a **replacement cache** until a live entry fails or is evicted.
- Buckets are lazily **split** when full and the local node's ID falls within their range.

```
Routing Table for local node "aabb..."
┌──────────────────────────────────────────────────────┐
│ Bucket 159  [peers with dist in (2^159, 2^160)]      │
│ Bucket 158  [peers with dist in (2^158, 2^159)]      │
│   ...                                                │
│ Bucket 0    [closest peers]                          │
└──────────────────────────────────────────────────────┘
```

### Bucket Assignment

A remote peer is assigned to bucket `i` where `i` is the position of the **highest differing bit** between the local ID and the remote ID.

```dart
final bucketIdx = Kademlia.bucketIndex(localId, remotePeerId);
```

### API

```dart
final table = RoutingTable(localId, k: 20);

// Add a peer (returns false if peer is self or bucket is full and can't split).
final added = table.add(PeerInfo(peerId: '...'));

// Remove.
table.remove(peerId);

// Find.
final peer = table.find(peerId);

// Closest N peers.
final closest = table.closest(targetId, count: 20);

// Record failure (evicts after 3 consecutive failures).
table.recordFailure(peerId);

// Mark as freshly seen.
table.touch(peerId);

// Get stale buckets (need refresh).
final stale = table.staleBuckets;
```

---

## Iterative Lookup

`DHTNetwork.findPeer(targetId)` performs a **parallel iterative FIND_NODE** lookup:

1. Start with `alpha` (default 3) closest known peers.
2. Send `FIND_NODE` RPCs to them in parallel.
3. Each response includes up to `k` closer peers.
4. Add newly discovered peers to the routing table and query them.
5. Repeat until `k` closest peers have all been queried or `maxLookupHops` is reached.

```dart
final result = await dhtNetwork.findPeer('aabbcc...40chars...');
if (result.found) {
  print('Found: ${result.peer!.peerId}');
  print('Hops: ${result.hops}');
}
```

`FIND_VALUE` follows the same pattern but short-circuits when a node returns the stored value.

---

## Key-Value Storage

```dart
// Store a value (replicated to k closest peers).
await dhtNetwork.put('my-key', 'my-value');

// Retrieve (local hit first, then iterative FIND_VALUE).
final value = await dhtNetwork.get('my-key');

// Delete locally (DHT records expire via TTL automatically).
dhtNetwork.delete('my-key');
```

### Records

Each stored value is wrapped in a `DHTRecord`:

```dart
DHTRecord({
  required String key,         // 40-char hex key (SHA-1 of original key string)
  required String value,       // serialised UTF-8 value
  required String publisherId, // storing node's peer ID
  required DateTime expiresAt, // expiration timestamp
  int sequence = 0,            // for conflict resolution
})
```

**Conflict resolution**: when two nodes store records under the same key, the one with the higher `sequence` number wins.

---

## Bootstrap Process

When `node.initialize()` is called with `bootstrapPeers`, the following occurs:

1. Seed `PeerInfo` objects for each bootstrap peer are added to the routing table.
2. A self-lookup (`findPeer(localId)`) is performed.
3. This causes the local node to discover its immediate neighbourhood in the ID space.
4. `DHTBootstrappedEvent` is emitted on completion.

```dart
P2PConfig(
  bootstrapPeers: [
    'aabbccdd11223344556677889900aabbccdd11223344',  // known seed node
  ],
)
```

Nodes starting with no bootstrap peers create an **isolated node** that will be discovered by others once they connect.

---

## RPCs

`DHTNetwork` handles four RPC types sent over the WebRTC data channels:

| RPC | Direction | Purpose |
|-----|-----------|---------|
| `PING` | → remote | Check if peer is alive |
| `FIND_NODE` | → remote | Get k closest nodes to a target |
| `FIND_VALUE` | → remote | Get a stored value or k closest nodes |
| `STORE` | → remote | Store a key/value record |

Each RPC has a corresponding response:

| Response | Description |
|----------|-------------|
| `PONG` | Alive confirmation |
| `FOUND_NODES` | List of closer peers |
| `FOUND_VALUE` | The stored value |
| `STORED` | Acknowledgement of storage |

**DHT messages are internally routed** through `P2PNode._handleDhtRpc` using `MessageType.dhtFindNode`, `dhtFindValue`, `dhtStore`, and `dhtPong` to avoid conflicts with application messages.

---

## Background Tasks

`DHTNetwork` runs three periodic background timers:

| Timer | Interval | Task |
|-------|----------|------|
| Bucket refresh | `DHTConfig.bucketRefreshInterval` (1 hour) | Looks up a random ID in each stale bucket to keep it fresh |
| Record republication | `DHTConfig.republishInterval` (1 hour) | Re-stores all non-expired records |
| Record expiration | 5 minutes | Removes expired records from the local store |

---

## DHT Configuration Reference

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `bootstrapPeers` | `List<String>` | `[]` | Seed peers (40-char hex IDs) |
| `bucketSize` | `int` | `20` | k parameter |
| `alpha` | `int` | `3` | Lookup parallelism |
| `replicationFactor` | `int` | `3` | Number of storage replicas |
| `maxLookupHops` | `int` | `20` | Max iterations per lookup |
| `bucketRefreshInterval` | `Duration` | `1 hour` | Bucket refresh period |
| `republishInterval` | `Duration` | `1 hour` | Record republish period |
| `valueTtl` | `Duration` | `24 hours` | Default record TTL |
| `rpcTimeout` | `Duration` | `10 sec` | Single RPC timeout |

---

## Key Classes

| Class | File | Purpose |
|-------|------|---------|
| `DHTNetwork` | `lib/src/dht/dht_network.dart` | Top-level DHT orchestrator |
| `RoutingTable` | `lib/src/dht/routing_table.dart` | 160-bucket routing table |
| `KBucket` | `lib/src/dht/bucket.dart` | Single k-bucket |
| `Kademlia` | `lib/src/dht/kademlia.dart` | XOR metric + ID utilities |
| `KademliaIdGenerator` | `lib/src/dht/kademlia.dart` | Stateful ID generator |
| `DHTRecord` | `lib/src/dht/dht_network.dart` | Stored key/value record |
| `FindPeerResult` | `lib/src/dht/dht_network.dart` | Lookup result type |
| `DHTConfig` | `lib/src/dht/dht_config.dart` | DHT configuration |
