/// Kademlia k-bucket implementation.
library;

import '../core/peer_info.dart';
import 'kademlia.dart';

// ─── Bucket Entry ─────────────────────────────────────────────────────────────

/// A single entry in a k-bucket, pairing a [PeerInfo] with the time it was
/// last confirmed alive.
class BucketEntry {
  /// The peer this entry describes.
  final PeerInfo peer;

  /// When we last received a valid response from this peer.
  DateTime lastSeen;

  /// How many consecutive failed RPCs we have recorded.
  int failureCount;

  /// Creates a [BucketEntry].
  BucketEntry({
    required this.peer,
    DateTime? lastSeen,
    this.failureCount = 0,
  }) : lastSeen = lastSeen ?? DateTime.now();

  /// Marks this entry as freshly seen.
  void touch() {
    lastSeen = DateTime.now();
    failureCount = 0;
  }

  /// Increments the failure count.
  void recordFailure() => failureCount++;

  /// Returns `true` if this peer should be considered dead.
  bool get isDead => failureCount >= 3;

  @override
  String toString() =>
      'BucketEntry(${peer.shortId}, failures: $failureCount, seen: $lastSeen)';
}

// ─── KBucket ─────────────────────────────────────────────────────────────────

/// A Kademlia k-bucket.
///
/// Stores at most [k] entries.  When full, newly discovered peers are kept in
/// a [replacementCache] and promoted only if an existing entry goes dead.
class KBucket {
  /// Maximum number of live entries (Kademlia parameter *k*).
  final int k;

  /// Lower bound of the ID range covered by this bucket (inclusive).
  final BigInt rangeMin;

  /// Upper bound of the ID range covered by this bucket (exclusive).
  final BigInt rangeMax;

  /// Live peers stored in this bucket, least-recently-seen at index 0.
  final List<BucketEntry> entries = [];

  /// Overflow cache of peer entries waiting to replace dead nodes.
  final List<BucketEntry> replacementCache = [];

  /// When this bucket was last refreshed (random lookup performed).
  DateTime lastRefresh;

  /// Creates a [KBucket].
  KBucket({
    required this.k,
    required this.rangeMin,
    required this.rangeMax,
  }) : lastRefresh = DateTime.now();

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Number of live entries.
  int get size => entries.length;

  /// Whether the bucket is full.
  bool get isFull => entries.length >= k;

  /// Whether the bucket needs a refresh (not refreshed in the last hour).
  bool get needsRefresh =>
      DateTime.now().difference(lastRefresh) > const Duration(hours: 1);

  /// Returns all live [PeerInfo] objects in this bucket.
  List<PeerInfo> get peers => entries.map((e) => e.peer).toList();

  /// Checks whether a peer with [peerId] is in the bucket.
  bool contains(String peerId) =>
      entries.any((e) => e.peer.peerId == peerId);

  /// Checks whether [id] falls within this bucket's ID range.
  bool coversId(String id) {
    final value = Kademlia.distance('0' * 40, id);
    return value >= rangeMin && value < rangeMax;
  }

  /// Inserts or updates a peer in this bucket.
  ///
  /// - If the peer already exists, it is moved to the tail (most-recently-seen)
  ///   and its entry is refreshed.
  /// - If the bucket is not full, the peer is appended.
  /// - If the bucket is full, the peer is added to [replacementCache] unless
  ///   there is a dead entry to evict first.
  ///
  /// Returns `true` if the peer was added to the live entries list.
  bool add(PeerInfo peer) {
    // Already present → update peer info and move to tail (most-recently-seen).
    final existingIndex =
        entries.indexWhere((e) => e.peer.peerId == peer.peerId);
    if (existingIndex != -1) {
      entries.removeAt(existingIndex);
      // Create a fresh entry with the updated PeerInfo so callers see the
      // latest displayName / address fields when they call find() / closest().
      entries.add(BucketEntry(peer: peer));
      return true;
    }

    // Bucket not full → append directly.
    if (!isFull) {
      entries.add(BucketEntry(peer: peer));
      return true;
    }

    // Bucket full → try to replace a dead entry.
    final deadIndex = entries.indexWhere((e) => e.isDead);
    if (deadIndex != -1) {
      entries.removeAt(deadIndex);
      entries.add(BucketEntry(peer: peer));
      return true;
    }

    // No room → put in replacement cache.
    _addToReplacement(peer);
    return false;
  }

  /// Removes the peer with [peerId] from the bucket (or the replacement cache).
  ///
  /// If a replacement-cache entry exists, it is promoted to fill the vacancy.
  ///
  /// Returns `true` if a peer was removed.
  bool remove(String peerId) {
    final idx = entries.indexWhere((e) => e.peer.peerId == peerId);
    if (idx != -1) {
      entries.removeAt(idx);
      _promoteReplacement();
      return true;
    }

    final cacheIdx =
        replacementCache.indexWhere((e) => e.peer.peerId == peerId);
    if (cacheIdx != -1) {
      replacementCache.removeAt(cacheIdx);
      return true;
    }

    return false;
  }

  /// Marks a failure for the peer with [peerId].
  ///
  /// If the peer accumulates too many failures ([BucketEntry.isDead]), it is
  /// evicted and the best replacement-cache entry is promoted.
  void recordFailure(String peerId) {
    final entry = entries.firstWhere(
      (e) => e.peer.peerId == peerId,
      orElse: () => BucketEntry(peer: PeerInfo(peerId: peerId)),
    );

    if (!entries.contains(entry)) return;

    entry.recordFailure();
    if (entry.isDead) {
      entries.remove(entry);
      _promoteReplacement();
    }
  }

  /// Marks the peer with [peerId] as freshly seen.
  void touch(String peerId) {
    final idx = entries.indexWhere((e) => e.peer.peerId == peerId);
    if (idx != -1) {
      final entry = entries.removeAt(idx);
      entry.touch();
      entries.add(entry);
    }
  }

  /// Marks this bucket as refreshed.
  void markRefreshed() => lastRefresh = DateTime.now();

  /// Returns all entries sorted by last-seen time, oldest first.
  List<BucketEntry> get leastRecentlySeenFirst =>
      List<BucketEntry>.from(entries)
        ..sort((a, b) => a.lastSeen.compareTo(b.lastSeen));

  // ─── Private Helpers ────────────────────────────────────────────────────────

  void _addToReplacement(PeerInfo peer) {
    // Remove stale entry if peer is already in cache.
    replacementCache.removeWhere((e) => e.peer.peerId == peer.peerId);
    replacementCache.add(BucketEntry(peer: peer));

    // Keep cache bounded.
    if (replacementCache.length > k) {
      replacementCache.removeAt(0);
    }
  }

  void _promoteReplacement() {
    if (replacementCache.isNotEmpty && !isFull) {
      entries.add(replacementCache.removeLast());
    }
  }

  @override
  String toString() =>
      'KBucket([${rangeMin.toRadixString(16).substring(0, 6)}…'
      '${rangeMax.toRadixString(16).substring(0, 6)}…], '
      'size: ${entries.length}/$k)';
}
