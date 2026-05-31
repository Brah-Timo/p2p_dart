/// Kademlia routing table — manages the set of k-buckets.
library;

import '../core/peer_info.dart';
import 'bucket.dart';
import 'kademlia.dart';

// ─── Routing Table ───────────────────────────────────────────────────────────

/// The complete Kademlia routing table for a single node.
///
/// Maintains up to 160 k-buckets, one per bit of ID space.  Buckets are
/// lazily created and split as needed.
class RoutingTable {
  /// The local node's ID.
  final String localId;

  /// Bucket size parameter *k*.
  final int k;

  /// The list of k-buckets, indexed by bucket index (0 = closest).
  final List<KBucket> _buckets = [];

  /// Creates a [RoutingTable] for [localId] with bucket size [k].
  RoutingTable(this.localId, {this.k = 20}) {
    // Initialise with a single bucket covering the full ID space.
    _buckets.add(
      KBucket(
        k: k,
        rangeMin: BigInt.zero,
        rangeMax: BigInt.two.pow(160),
      ),
    );
  }

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Total number of peers across all buckets.
  int get size => _buckets.fold(0, (sum, b) => sum + b.size);

  /// All known [PeerInfo] objects in the routing table.
  List<PeerInfo> get allPeers =>
      _buckets.expand((b) => b.peers).toList();

  /// Adds or updates a [PeerInfo] in the routing table.
  ///
  /// Returns `true` if the peer was stored in a live bucket entry.
  bool add(PeerInfo peer) {
    if (peer.peerId == localId) return false; // never add self
    final bucket = _bucketFor(peer.peerId);
    final added = bucket.add(peer);

    if (!added && _canSplit(bucket)) {
      _split(bucket);
      return add(peer); // retry after split
    }

    return added;
  }

  /// Removes the peer with [peerId] from the routing table.
  ///
  /// Returns `true` if a peer was removed.
  bool remove(String peerId) {
    return _bucketFor(peerId).remove(peerId);
  }

  /// Looks up a single peer by ID.
  PeerInfo? find(String peerId) {
    final bucket = _bucketFor(peerId);
    try {
      return bucket.entries
          .firstWhere((e) => e.peer.peerId == peerId)
          .peer;
    } catch (_) {
      return null;
    }
  }

  /// Returns the [count] closest peers to [targetId] from the routing table,
  /// sorted by XOR distance ascending.
  List<PeerInfo> closest(String targetId, {int count = 20}) {
    final all = allPeers;
    return Kademlia.closestN(
      targetId: targetId,
      candidates: all,
      getId: (p) => p.peerId,
      count: count,
    );
  }

  /// Records a failed RPC to the peer with [peerId].
  void recordFailure(String peerId) {
    _bucketFor(peerId).recordFailure(peerId);
  }

  /// Marks the peer with [peerId] as freshly seen.
  void touch(String peerId) {
    _bucketFor(peerId).touch(peerId);
  }

  /// Returns buckets that need to be refreshed.
  List<KBucket> get staleBuckets =>
      _buckets.where((b) => b.needsRefresh).toList();

  /// Returns a random target ID within a bucket's range for refresh lookups.
  String randomIdInBucket(KBucket bucket) {
    final range = bucket.rangeMax - bucket.rangeMin;
    final offset = BigInt.from(DateTime.now().microsecondsSinceEpoch) % range;
    final value = bucket.rangeMin + offset;
    return value.toRadixString(16).padLeft(40, '0').substring(0, 40);
  }

  // ─── Private Helpers ────────────────────────────────────────────────────────

  /// Returns the bucket responsible for [peerId].
  KBucket _bucketFor(String peerId) {
    // Walk backwards from the highest bucket index to find the matching range.
    for (final bucket in _buckets.reversed) {
      if (bucket.coversId(peerId)) return bucket;
    }
    return _buckets.last;
  }

  /// Returns `true` if the bucket can be split.
  ///
  /// A bucket is splittable only if it covers the local node's own ID range
  /// (i.e., the local node would fall into one of the resulting halves).
  bool _canSplit(KBucket bucket) {
    // Only split if the local node's ID is within this bucket's range.
    return bucket.coversId(localId);
  }

  /// Splits [bucket] into two halves.
  void _split(KBucket bucket) {
    final mid = (bucket.rangeMin + bucket.rangeMax) >> 1;

    final left = KBucket(k: k, rangeMin: bucket.rangeMin, rangeMax: mid);
    final right = KBucket(k: k, rangeMin: mid, rangeMax: bucket.rangeMax);

    // Redistribute existing entries.
    for (final entry in [...bucket.entries, ...bucket.replacementCache]) {
      if (left.coversId(entry.peer.peerId)) {
        left.add(entry.peer);
      } else {
        right.add(entry.peer);
      }
    }

    final idx = _buckets.indexOf(bucket);
    _buckets
      ..removeAt(idx)
      ..insert(idx, right)
      ..insert(idx, left);
  }

  @override
  String toString() =>
      'RoutingTable(local: ${localId.substring(0, 8)}…, '
      'buckets: ${_buckets.length}, peers: $size)';
}
